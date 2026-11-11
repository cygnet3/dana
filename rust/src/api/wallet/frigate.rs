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
            FrigateEvent::Unconfirmed {
                txid,
                discovered_outputs,
            } => {
                // phase-2 contract: mempool discoveries enter the candidate
                // pipeline; wallet state is created only on the confirmation
                // notification, and candidates never advance the checkpoint
                pump.record_mempool(txid, discovered_outputs)?
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

/// Liveness probe for the background monitor: true while a monitor task is
/// spawned AND still running (holding the subscription). A finished task —
/// connection death included — reports false, so the Dart side restarts the
/// monitor from the persisted checkpoint instead of trusting a dead tail.
#[flutter_rust_bridge::frb(sync)]
pub fn frigate_monitor_running() -> bool {
    FRIGATE_MONITOR
        .lock()
        .unwrap()
        .as_ref()
        .map_or(false, |handle| !handle.is_finished())
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
            FrigateEvent::Unconfirmed {
                txid,
                discovered_outputs,
            } => {
                // phase-2 contract: mempool candidates never create wallet
                // state directly, never advance the checkpoint and never
                // touch the progress bar; the mined transaction is
                // re-delivered as Confirmed (real height) and created once.
                if let Err(err) = pump.record_mempool(txid, discovered_outputs) {
                    log::warn!("frigate monitor: mempool candidate failed: {err}");
                }
            }
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

    // ---- phase-2/3 acceptance tests (decision-record amendment 2026-11-10) ----

    use crate::state::RecordingSink;
    use spdk_wallet::bitcoin::secp256k1::Scalar;
    use spdk_wallet::bitcoin::{Amount, ScriptBuf, TxOut, Txid};
    use spdk_wallet::scanner::{DiscoveredOutput, ScanResult};

    fn test_txid(v: u8) -> Txid {
        Txid::from_str(&format!("{v:064x}")).unwrap()
    }

    fn discovered_output(v: u8) -> (OutPoint, DiscoveredOutput) {
        (
            OutPoint::new(test_txid(v), 0),
            DiscoveredOutput {
                txout: TxOut {
                    value: Amount::from_sat(50_000),
                    script_pubkey: ScriptBuf::new(),
                },
                tweak: Scalar::ONE,
                label: None,
            },
        )
    }

    fn confirmed_result(
        outpoint: OutPoint,
        output: &DiscoveredOutput,
        height: u32,
    ) -> FrigateEvent {
        FrigateEvent::Confirmed(ScanResult {
            blkheight: test_height(height),
            blkhash: test_hash(),
            discovered_inputs: HashSet::new(),
            discovered_outputs: HashMap::from([(outpoint, output.clone())]),
        })
    }

    /// Acceptance (a): mempool → notify exact-once. A height<=0 entry
    /// registers a candidate (never wallet state); the confirmation
    /// notification (scanner re-delivery at a real height) creates the state
    /// exactly once; the phase-1 re-report of the same output must not
    /// duplicate it.
    #[tokio::test]
    async fn mempool_to_notify_exact_once() {
        let _guard = FLAG_LOCK.lock().unwrap();
        KEEP_SYNCING.store(true, Ordering::Relaxed);
        let sink = RecordingSink::default();
        let mut pump = SyncUpdatePump::with_sink(0, Box::new(sink.clone()));
        let mut tip = None;

        let (outpoint, output) = discovered_output(1);
        let outputs = HashMap::from([(outpoint, output.clone())]);

        // phase 2: the mempool entry arrives over the key-bearing subscription
        let events = futures::stream::iter(vec![
            FrigateEvent::Tip {
                height: test_height(800_002),
                hash: test_hash(),
            },
            FrigateEvent::Unconfirmed {
                txid: test_txid(1),
                discovered_outputs: outputs.clone(),
            },
        ]);
        drive_frigate_events(events, &mut pump, &mut tip).await.unwrap();

        assert_eq!(
            pump.mempool_candidate_count(),
            1,
            "mempool discovery must register a candidate, not be dropped"
        );
        assert!(
            sink.updates.lock().unwrap().is_empty(),
            "a candidate must not create wallet state before confirmation"
        );

        // phase 3: confirmation notification — the scanner re-delivers the
        // mined transaction as a Confirmed event at the real height
        let events = futures::stream::iter(vec![confirmed_result(
            outpoint,
            &output,
            800_003,
        )]);
        drive_frigate_events(events, &mut pump, &mut tip).await.unwrap();

        let updates = sink.updates.lock().unwrap();
        assert_eq!(updates.len(), 1, "state must be created exactly once");
        assert_eq!(
            updates[0].blkheight, 800_003,
            "candidate state carries the confirmation height"
        );
        assert_eq!(updates[0].found_outputs.len(), 1);
        drop(updates);

        // the next phase-1 scan re-reports the same output as Confirmed
        let events =
            futures::stream::iter(vec![confirmed_result(outpoint, &output, 800_003)]);
        drive_frigate_events(events, &mut pump, &mut tip).await.unwrap();

        let updates = sink.updates.lock().unwrap();
        assert_eq!(
            updates.len(),
            1,
            "phase-1 re-report must not duplicate wallet state (exact-once)"
        );
        drop(updates);
        assert_eq!(pump.emitted_output_count(), 1);
    }

    /// Acceptance (c): a mempool candidate never advances the checkpoint and
    /// never touches the progress bar; confirmation emits at the real height.
    #[tokio::test]
    async fn mempool_candidate_never_advances_checkpoint_or_bar() {
        let _guard = FLAG_LOCK.lock().unwrap();
        KEEP_SYNCING.store(true, Ordering::Relaxed);
        let sink = RecordingSink::default();
        let mut pump = SyncUpdatePump::with_sink(0, Box::new(sink.clone()));
        let mut tip = None;

        let (outpoint, output) = discovered_output(2);

        let events = futures::stream::iter(vec![
            FrigateEvent::Tip {
                height: test_height(800_002),
                hash: test_hash(),
            },
            FrigateEvent::Unconfirmed {
                txid: test_txid(2),
                discovered_outputs: HashMap::from([(outpoint, output)]),
            },
        ]);
        drive_frigate_events(events, &mut pump, &mut tip).await.unwrap();

        assert_eq!(
            pump.mempool_candidate_count(),
            1,
            "candidate must be registered (not dropped)"
        );
        assert!(
            sink.updates.lock().unwrap().is_empty(),
            "mempool activity must not create wallet state"
        );
        assert_eq!(
            pump.last_emitted_height(),
            0,
            "mempool activity must not advance the checkpoint"
        );
        assert!(
            pump.progress_log().is_empty(),
            "mempool activity must not touch the progress bar"
        );

        // confirmation: state emitted at the real height only
        let (outpoint, output) = discovered_output(2);
        let events =
            futures::stream::iter(vec![confirmed_result(outpoint, &output, 800_003)]);
        drive_frigate_events(events, &mut pump, &mut tip).await.unwrap();

        let updates = sink.updates.lock().unwrap();
        assert_eq!(updates.len(), 1);
        assert_eq!(
            updates[0].blkheight, 800_003,
            "candidate state is created at the confirmation height, never a mempool sentinel"
        );
        drop(updates);
        assert_eq!(pump.last_emitted_height(), 800_003);
        assert!(
            pump.progress_log().iter().all(|h| *h > 0),
            "the progress bar never rewinds to a mempool sentinel height"
        );
    }

    // ---- phase-3 electrum confirmation tracking (Sub-C) ----

    use crate::api::wallet::frigate_confirm::matched_confirmations;
    use electrum_streaming_client::response::{ConfirmedTx, MempoolTx, Tx as HistoryTx};

    fn test_script() -> ScriptBuf {
        ScriptBuf::from_hex("00140000000000000000000000000000000000000000").unwrap()
    }

    /// The candidate registry exposes (script, txid) pairs so the phase-3
    /// confirmation tracker can register every distinct mempool-discovered
    /// output script with the regular electrum server.
    #[test]
    fn mempool_candidate_exposes_scripts_for_registration() {
        let mut pump = SyncUpdatePump::with_sink(0, Box::new(RecordingSink::default()));
        let (outpoint, mut output) = discovered_output(3);
        output.txout.script_pubkey = test_script();
        pump.record_mempool(test_txid(3), HashMap::from([(outpoint, output)]))
            .unwrap();

        let pairs = pump.candidate_script_txids();
        assert_eq!(
            pairs.len(),
            1,
            "one candidate output script must be exposed for registration"
        );
        assert_eq!(pairs[0], (test_script(), test_txid(3)));
    }

    /// Acceptance (a) electrum leg: the confirmation notification (candidate
    /// txid matched in the electrum scripthash history at a real height)
    /// creates wallet state exactly once; a duplicate electrum notification
    /// and the phase-1 Confirmed re-report both dedupe to nothing.
    #[tokio::test]
    // FLAG_LOCK: drive_frigate_events reads the global KEEP_SYNCING flag.
    #[allow(clippy::await_holding_lock)]
    async fn electrum_confirmation_creates_state_exactly_once() {
        let _guard = FLAG_LOCK.lock().unwrap();
        KEEP_SYNCING.store(true, Ordering::Relaxed);
        let sink = RecordingSink::default();
        let mut pump = SyncUpdatePump::with_sink(0, Box::new(sink.clone()));
        let mut tip = None;

        let (outpoint, output) = discovered_output(4);
        pump.record_mempool(
            test_txid(4),
            HashMap::from([(outpoint, output.clone())]),
        )
        .unwrap();
        assert!(
            sink.updates.lock().unwrap().is_empty(),
            "registration must not create wallet state"
        );

        // electrum: the candidate txid shows up mined at 800_003
        let emitted = pump
            .confirm_candidates(&HashSet::from([test_txid(4)]), 800_003, "blkhash")
            .unwrap();
        assert_eq!(emitted, 1, "the confirmation must emit one state update");

        let updates = sink.updates.lock().unwrap();
        assert_eq!(updates.len(), 1);
        assert_eq!(
            updates[0].blkheight, 800_003,
            "candidate state carries the mined height from the electrum history"
        );
        assert_eq!(updates[0].found_outputs.len(), 1);
        assert_eq!(
            updates[0].found_outputs[0].outpoint.txid,
            test_txid(4).to_string()
        );
        drop(updates);

        // duplicate electrum notification for the same txid: nothing emitted
        let emitted = pump
            .confirm_candidates(&HashSet::from([test_txid(4)]), 800_003, "blkhash")
            .unwrap();
        assert_eq!(emitted, 0, "duplicate confirmation must not re-emit");

        // the next phase-1 scan re-reports the same output as Confirmed
        let events =
            futures::stream::iter(vec![confirmed_result(outpoint, &output, 800_003)]);
        drive_frigate_events(events, &mut pump, &mut tip).await.unwrap();
        assert_eq!(
            sink.updates.lock().unwrap().len(),
            1,
            "phase-1 re-report must not duplicate wallet state (exact-once)"
        );
        assert_eq!(pump.emitted_output_count(), 1);
    }

    /// A candidate output already emitted by a racing phase-1 Confirmed
    /// report is not re-emitted when the electrum notification lands; only
    /// the still-unemitted outputs of the same candidate are emitted
    /// (per-outpoint exact-once).
    #[test]
    fn electrum_confirmation_emits_only_unemitted_outputs() {
        let sink = RecordingSink::default();
        let mut pump = SyncUpdatePump::with_sink(0, Box::new(sink.clone()));

        let (o1, mut out1) = discovered_output(5);
        out1.txout.script_pubkey = test_script();
        let (o2, mut out2) = discovered_output(6);
        out2.txout.script_pubkey = test_script();

        pump.record_mempool(
            test_txid(5),
            HashMap::from([(o1, out1.clone()), (o2, out2.clone())]),
        )
        .unwrap();

        // phase-1 Confirmed delivery wins the race for o2
        pump.record(
            ScanResult {
                blkheight: test_height(800_003),
                blkhash: test_hash(),
                discovered_inputs: HashSet::new(),
                discovered_outputs: HashMap::from([(o2, out2)]),
            },
            false,
        )
        .unwrap();
        assert_eq!(sink.updates.lock().unwrap().len(), 1);

        // the electrum confirmation covers the whole candidate txid: only o1
        // is still unemitted, so only o1 is emitted now
        let emitted = pump
            .confirm_candidates(&HashSet::from([test_txid(5)]), 800_003, "blkhash")
            .unwrap();
        assert_eq!(emitted, 1);

        let updates = sink.updates.lock().unwrap();
        assert_eq!(updates.len(), 2);
        assert_eq!(
            updates[1].found_outputs.len(),
            1,
            "the already-emitted output must not be re-emitted"
        );
        assert_eq!(
            updates[1].found_outputs[0].outpoint.txid,
            test_txid(5).to_string()
        );
    }

    /// The electrum history matcher: only CONFIRMED entries (height > 0)
    /// whose txid is a watched candidate count as confirmations; mempool
    /// entries (not yet mined) and foreign txids never do.
    #[test]
    fn history_matcher_only_confirms_watched_confirmed_txids() {
        let watched = HashSet::from([test_txid(7), test_txid(8)]);
        let history = vec![
            HistoryTx::Confirmed(ConfirmedTx {
                txid: test_txid(7),
                height: Height::from_consensus(800_004).unwrap(),
            }),
            HistoryTx::Confirmed(ConfirmedTx {
                txid: test_txid(9),
                height: Height::from_consensus(800_004).unwrap(),
            }),
            HistoryTx::Mempool(MempoolTx {
                txid: test_txid(8),
                fee: Amount::from_sat(1000),
                confirmed_inputs: true,
            }),
        ];
        let matched = matched_confirmations(&history, &watched);
        assert_eq!(
            matched,
            HashSet::from([test_txid(7)]),
            "only the watched, confirmed txid confirms"
        );
    }
}
