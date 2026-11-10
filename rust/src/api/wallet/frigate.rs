use std::collections::{HashMap, HashSet};
use std::sync::atomic::Ordering;
use std::sync::Mutex;
use std::time::Duration;

use anyhow::Result;
use futures::Stream;
use futures::StreamExt as _;
use lazy_static::lazy_static;
use spdk_wallet::bitcoin::absolute::Height;
use spdk_wallet::bitcoin::{BlockHash, OutPoint, ScriptBuf};

use crate::api::structs::frigate_scan_outcome::FrigateScanOutcome;
use crate::state::SyncUpdatePump;
use crate::stream::{send_sync_progress, send_sync_tip};
use crate::wallet::KEEP_SYNCING;

use super::SpWallet;
use backend_frigate::FrigateClient;
use frigate::{FrigateEvent, FrigateHandle, FrigateScanner};

/// Request timeout for the keyless tip probe. Short on purpose: a hung
/// server must surface as a probe failure (D8 offline banner) instead of a
/// stalled wake.
const PROBE_TIMEOUT: Duration = Duration::from_secs(5);

lazy_static! {
    /// Background monitor task; aborting it drops the `FrigateHandle`, which
    /// aborts the scanner worker and closes the frigate connection.
    static ref FRIGATE_MONITOR: Mutex<Option<tokio::task::JoinHandle<()>>> = Mutex::new(None);
}

/// Keyless chain-tip probe for a frigate server: connect, negotiate the
/// protocol version, fetch the tip via `blockchain.headers.subscribe`, drop
/// the connection.
///
/// Key-safe by construction (D10): no wallet receiver, no scan key material,
/// and the key-bearing silent-payments `subscribe` is unreachable from this
/// path — only public chain data crosses the wire. Also serves as the URL
/// validation primitive (parse + reachability) for the settings UI. The tip
/// notifications the headers subscription leaves flowing die with the
/// dropped client.
pub async fn frigate_tip_probe(url: String) -> Result<(u32, String)> {
    let client = FrigateClient::connect(&url, Some(PROBE_TIMEOUT)).await?;
    let (height, hash) = client.block_height().await?;
    drop(client);
    Ok((height.to_consensus_u32(), hash.to_string()))
}

/// An owned output the frigate scanner keeps watching for spends.
///
/// Frigate re-delivers silent payment history only from the requested start
/// height, so the scanner re-subscribes these outputs' scripts on `start` and
/// sweeps their history once — that is what makes spends detected while the
/// wallet was offline surface as `FrigateEvent::Spent`.
#[derive(Debug, Clone)]
pub struct WatchedOutput {
    pub outpoint: crate::api::structs::outpoint::OutPoint,
    pub script: Vec<u8>,
}

impl SpWallet {
    async fn build_frigate_scanner(
        &self,
        frigate_url: String,
        watched_outputs: Vec<WatchedOutput>,
    ) -> Result<FrigateScanner> {
        let mut previous_outputs: HashMap<ScriptBuf, HashSet<OutPoint>> = HashMap::new();
        for watched in watched_outputs {
            let outpoint: OutPoint = watched.outpoint.into();
            previous_outputs
                .entry(ScriptBuf::from_bytes(watched.script))
                .or_default()
                .insert(outpoint);
        }

        FrigateScanner::new(
            frigate_url,
            self.client.scan_key(),
            self.client.receiver(),
            // Dana does not use silent payment labels yet
            None,
            previous_outputs,
        )
        .await
    }

    /// One-shot frigate sync: subscribe from `from_height`, forward confirmed
    /// discoveries and spends through the sync streams, and return once the
    /// historical catch-up completes (checkpoint advanced to the tip).
    ///
    /// Returns a typed outcome instead of an error for connection loss: a
    /// death before `CaughtUp` (including a silent channel close) maps to
    /// [`FrigateScanOutcome::Disconnected`], not to `Err` — the checkpoint
    /// already reflects every confirmed block the pump emitted (D8).
    ///
    /// Cancellation reuses the existing `KEEP_SYNCING` flag: the flag is
    /// armed at entry and checked each loop iteration, so `interrupt_sync()`
    /// (and its whole existing interrupt plumbing, IPC included) stops a
    /// frigate scan without any new API. An interrupt returns
    /// `Disconnected` *without* finalize.
    ///
    /// Drop-in for the hourly wake cycle; the scanner connection is closed on
    /// return. The frigate server only learns the scan key — no address or
    /// spend key ever crosses the wire.
    pub async fn sync_via_frigate(
        &self,
        frigate_url: String,
        from_height: u32,
        dust_limit: u64,
        watched_outputs: Vec<WatchedOutput>,
    ) -> Result<FrigateScanOutcome> {
        KEEP_SYNCING.store(true, Ordering::Relaxed);

        let scanner = self
            .build_frigate_scanner(frigate_url, watched_outputs)
            .await?;
        let handle = scanner.start(Height::from_consensus(from_height)?);
        let mut pump = SyncUpdatePump::new(dust_limit);
        let mut tip: Option<(Height, BlockHash)> = None;
        drive_frigate_events(handle, &mut pump, &mut tip).await
    }

    /// Continuous frigate monitor for the foreground service: keeps the
    /// subscription open and streams live block/mempool/tip/spend events
    /// until `stopFrigateMonitor()` is called or the connection ends.
    ///
    /// Safe to call again: replaces any running monitor.
    pub async fn start_frigate_monitor(
        &self,
        frigate_url: String,
        from_height: u32,
        dust_limit: u64,
        watched_outputs: Vec<WatchedOutput>,
    ) -> Result<()> {
        let scanner = self
            .build_frigate_scanner(frigate_url, watched_outputs)
            .await?;
        let handle = scanner.start(Height::from_consensus(from_height)?);

        let mut guard = FRIGATE_MONITOR.lock().unwrap();
        if let Some(old) = guard.take() {
            old.abort();
        }
        *guard = Some(tokio::spawn(async move {
            monitor_pump(handle, dust_limit).await;
        }));

        Ok(())
    }
}

/// Drives the scanner event stream to a typed outcome (D8).
///
/// Split out from [`SpWallet::sync_via_frigate`] so the outcome mapping can
/// be unit-tested against synthetic event streams; a live [`FrigateHandle`]
/// is just another `Stream<Item = FrigateEvent>` and behaves identically.
async fn drive_frigate_events<S>(
    mut events: S,
    pump: &mut SyncUpdatePump,
    tip: &mut Option<(Height, BlockHash)>,
) -> Result<FrigateScanOutcome>
where
    S: Stream<Item = FrigateEvent> + Unpin,
{
    while let Some(event) = events.next().await {
        if !KEEP_SYNCING.load(Ordering::Relaxed) {
            // interrupted: no finalize; the checkpoint stays at the last
            // Confirmed boundary and the next backend resumes from there.
            return Ok(FrigateScanOutcome::Disconnected {
                reason: "interrupted".to_string(),
            });
        }
        match event {
            FrigateEvent::Tip { height, hash } => {
                *tip = Some((height, hash));
                send_sync_tip(height.to_consensus_u32());
            }
            FrigateEvent::Confirmed(scan_result) => pump.record(scan_result, false)?,
            FrigateEvent::Spent(spent) => pump.record_spent(spent)?,
            FrigateEvent::CaughtUp => {
                if let Some((height, hash)) = *tip {
                    pump.finalize(height, hash)?;
                }
                return Ok(FrigateScanOutcome::Completed);
            }
            FrigateEvent::Disconnected(reason) => {
                return Ok(FrigateScanOutcome::Disconnected { reason });
            }
            FrigateEvent::Unconfirmed { txid, .. } => {
                // mempool discoveries are re-reported as Confirmed once
                // mined; Dana's state layer only tracks confirmed outputs
                log::debug!("frigate: mempool discovery {txid} deferred until confirmation");
            }
        }
    }

    // Silent channel close before CaughtUp (D8): a dead connection must
    // not look like a completed sync.
    Ok(FrigateScanOutcome::Disconnected {
        reason: "connection closed".to_string(),
    })
}

/// Stop the background frigate monitor (no-op if none is running).
#[flutter_rust_bridge::frb(sync)]
pub fn stop_frigate_monitor() {
    if let Some(handle) = FRIGATE_MONITOR.lock().unwrap().take() {
        handle.abort();
    }
}

async fn monitor_pump(mut handle: FrigateHandle, dust_limit: u64) {
    let mut pump = SyncUpdatePump::new(dust_limit);
    let mut caught_up = false;

    while let Some(event) = handle.next().await {
        match event {
            FrigateEvent::Tip { height, hash } => {
                // before CaughtUp the tip is progress only; afterwards each new
                // tip keeps the wallet checkpoint advancing live
                let result = if caught_up {
                    pump.finalize(height, hash)
                } else {
                    send_sync_progress(height.to_consensus_u32());
                    Ok(())
                };
                if let Err(err) = result {
                    log::warn!("frigate monitor: tip handling failed: {err}");
                }
            }
            FrigateEvent::Confirmed(scan_result) => {
                if let Err(err) = pump.record(scan_result, false) {
                    log::warn!("frigate monitor: discovery handling failed: {err}");
                }
            }
            FrigateEvent::Spent(spent) => {
                if let Err(err) = pump.record_spent(spent) {
                    log::warn!("frigate monitor: spend handling failed: {err}");
                }
            }
            FrigateEvent::CaughtUp => caught_up = true,
            FrigateEvent::Disconnected(reason) => {
                log::warn!("frigate monitor disconnected: {reason}");
                break;
            }
            FrigateEvent::Unconfirmed { .. } => {}
        }
    }
}

#[cfg(test)]
// FLAG_LOCK deliberately serializes the global KEEP_SYNCING static across
// test runtimes; the std MutexGuard is intentionally held across the drives
// so no other test can flip the flag mid-run.
#[allow(clippy::await_holding_lock)]
mod tests {
    use super::*;
    use std::str::FromStr;
    use std::sync::Mutex as StdMutex;

    /// Serialises tests that touch the global `KEEP_SYNCING` flag.
    static FLAG_LOCK: StdMutex<()> = StdMutex::new(());

    fn test_height(v: u32) -> Height {
        Height::from_consensus(v).unwrap()
    }

    fn test_hash() -> BlockHash {
        BlockHash::from_str(&"0".repeat(64)).unwrap()
    }

    /// Silent channel close before CaughtUp maps to `Disconnected`, never to
    /// a success-looking outcome (D8).
    #[tokio::test]
    async fn silent_close_maps_to_disconnected() {
        let _guard = FLAG_LOCK.lock().unwrap();
        KEEP_SYNCING.store(true, Ordering::Relaxed);
        let mut pump = SyncUpdatePump::new(0);
        let mut tip = None;
        let outcome = drive_frigate_events(
            futures::stream::iter(Vec::<FrigateEvent>::new()),
            &mut pump,
            &mut tip,
        )
        .await
        .unwrap();
        match outcome {
            FrigateScanOutcome::Disconnected { reason } => {
                assert_eq!(reason, "connection closed");
            }
            FrigateScanOutcome::Completed => panic!("silent close must not look like success"),
        }
    }

    /// `CaughtUp` maps to `Completed` and finalizes at the tip. No stream sink
    /// is registered in tests, so `pump.finalize` fails with "Stream sink not
    /// available" — the error proves the Completed mapping reached the
    /// finalize call (a Disconnected mapping would have returned `Ok`).
    #[tokio::test]
    async fn caught_up_maps_to_completed_and_finalizes() {
        let _guard = FLAG_LOCK.lock().unwrap();
        KEEP_SYNCING.store(true, Ordering::Relaxed);
        let mut pump = SyncUpdatePump::new(0);
        let mut tip = None;
        let events = futures::stream::iter(vec![
            FrigateEvent::Tip {
                height: test_height(800_002),
                hash: test_hash(),
            },
            FrigateEvent::CaughtUp,
        ]);
        let err = drive_frigate_events(events, &mut pump, &mut tip)
            .await
            .expect_err("finalize must be attempted on CaughtUp");
        assert!(err.to_string().contains("Stream sink not available"));
    }

    /// A `Disconnected` event maps to the typed outcome carrying its reason.
    #[tokio::test]
    async fn disconnected_event_maps_to_disconnected() {
        let _guard = FLAG_LOCK.lock().unwrap();
        KEEP_SYNCING.store(true, Ordering::Relaxed);
        let mut pump = SyncUpdatePump::new(0);
        let mut tip = None;
        let events = futures::stream::iter(vec![
            FrigateEvent::Tip {
                height: test_height(800_002),
                hash: test_hash(),
            },
            FrigateEvent::Disconnected("boom".to_string()),
        ]);
        let outcome = drive_frigate_events(events, &mut pump, &mut tip)
            .await
            .unwrap();
        match outcome {
            FrigateScanOutcome::Disconnected { reason } => assert_eq!(reason, "boom"),
            FrigateScanOutcome::Completed => panic!("disconnect must not look like success"),
        }
    }

    /// An interrupt (existing `KEEP_SYNCING` path) returns `Disconnected`
    /// *without* finalize: the `Ok` return (not the no-sink finalize error)
    /// proves no finalize was attempted, so the checkpoint stays at the last
    /// Confirmed boundary (D9 mid-scan switch).
    #[tokio::test]
    async fn interrupt_returns_disconnected_without_finalize() {
        let _guard = FLAG_LOCK.lock().unwrap();
        KEEP_SYNCING.store(false, Ordering::Relaxed);
        let mut pump = SyncUpdatePump::new(0);
        let mut tip = None;
        let events = futures::stream::iter(vec![
            FrigateEvent::Tip {
                height: test_height(800_002),
                hash: test_hash(),
            },
            FrigateEvent::CaughtUp,
        ]);
        let outcome = drive_frigate_events(events, &mut pump, &mut tip)
            .await
            .unwrap();
        match outcome {
            FrigateScanOutcome::Disconnected { reason } => assert_eq!(reason, "interrupted"),
            FrigateScanOutcome::Completed => panic!("interrupt must not finalize"),
        }
    }

    /// D10 URL validation: a malformed URL fails at socket-addr parsing
    /// before any I/O — the keyless probe never reaches the network with a
    /// typo'd endpoint (and it carries no scan key at all).
    #[tokio::test]
    async fn probe_rejects_bad_url_before_any_io() {
        assert!(frigate_tip_probe("not a url".to_string()).await.is_err());
        assert!(frigate_tip_probe(String::new()).await.is_err());
    }
}
