use std::collections::{HashMap, HashSet};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::Result;
use futures::channel::mpsc::unbounded;
use futures::Stream;
use futures::StreamExt as _;
use lazy_static::lazy_static;
use spdk_wallet::bitcoin::absolute::Height;
use spdk_wallet::bitcoin::{BlockHash, OutPoint, ScriptBuf};

use crate::api::structs::frigate_scan_outcome::FrigateScanOutcome;
use crate::api::wallet::frigate_confirm::run_confirmation_tracker;
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
            .build_frigate_scanner(frigate_url.clone(), watched_outputs)
            .await?;
        let handle = scanner.start(Height::from_consensus(from_height)?);

        let mut guard = FRIGATE_MONITOR.lock().unwrap();
        if let Some(old) = guard.take() {
            old.abort();
        }
        *guard = Some(tokio::spawn(async move {
            monitor_pump(handle, dust_limit, frigate_url).await;
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

async fn monitor_pump(handle: FrigateHandle, dust_limit: u64, electrum_url: String) {
    let pump = Arc::new(Mutex::new(SyncUpdatePump::new(dust_limit)));
    run_monitor(handle, pump, electrum_url).await;
}

/// Monitor event loop over a pump shared with the phase-3 confirmation
/// tracker: every mempool discovery registers its output scripts with the
/// regular electrum server (decision-record amendment 2026-11-10, phase 3)
/// while the pump keeps the exact-once dedup against phase-1 `Confirmed`
/// re-reports.
///
/// Split out from [`monitor_pump`] so tests can inject a recording pump.
pub(crate) async fn run_monitor(
    handle: FrigateHandle,
    pump: Arc<Mutex<SyncUpdatePump>>,
    electrum_url: String,
) {
    let mut handle = handle;
    let (registrations_tx, registrations_rx) =
        unbounded::<(ScriptBuf, spdk_wallet::bitcoin::Txid)>();
    tokio::spawn(run_confirmation_tracker(
        electrum_url,
        pump.clone(),
        registrations_rx,
    ));

    let mut caught_up = false;
    while let Some(event) = handle.next().await {
        match event {
            FrigateEvent::Tip { height, hash } => {
                // before CaughtUp the tip is progress only; afterwards each new
                // tip keeps the wallet checkpoint advancing live
                let result = if caught_up {
                    pump.lock().unwrap().finalize(height, hash)
                } else {
                    send_sync_progress(height.to_consensus_u32());
                    Ok(())
                };
                if let Err(err) = result {
                    log::warn!("frigate monitor: tip handling failed: {err}");
                }
            }
            FrigateEvent::Confirmed(scan_result) => {
                if let Err(err) = pump.lock().unwrap().record(scan_result, false) {
                    log::warn!("frigate monitor: discovery handling failed: {err}");
                }
            }
            FrigateEvent::Spent(spent) => {
                if let Err(err) = pump.lock().unwrap().record_spent(spent) {
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
                // touch the progress bar. Phase-3: every output script is
                // registered with the regular electrum server; the
                // confirmation notification creates the state exactly once
                // (deduped against the phase-1 re-report).
                for output in discovered_outputs.values() {
                    let _ = registrations_tx
                        .unbounded_send((output.txout.script_pubkey.clone(), txid));
                }
                if let Err(err) = pump.lock().unwrap().record_mempool(txid, discovered_outputs) {
                    log::warn!("frigate monitor: mempool candidate failed: {err}");
                }
            }
        }
    }
    // The monitor is over; dropping `registrations_tx` ends the tracker.
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

    // ---- Sub-C gate: regtest-rig end-to-end (acceptance (a), electrum leg) ----

    /// Minimal electrum server for the phase-3 leg, speaking the exact wire
    /// subset the confirmation tracker uses: server.version handshake,
    /// blockchain.scripthash.subscribe (+ status notifications),
    /// blockchain.scripthash.get_history, blockchain.block.header.
    ///
    /// Why a mock: frigate 1.4.1 rejects scripthash.subscribe without a
    /// configured backendElectrumServer and no regtest electrs exists on
    /// this rig. The tracker only needs the electrum PROTOCOL, so the mock
    /// stands in for the regular electrum server (server selection is an
    /// implementation decision per the amendment) while frigate keeps
    /// serving phases 1-2 for real.
    struct MockElectrum {
        addr: std::net::SocketAddr,
        state: Arc<Mutex<MockElectrumState>>,
        clients: Arc<Mutex<Vec<std::sync::mpsc::Sender<String>>>>,
    }

    struct MockElectrumState {
        subscribed: Vec<String>,
        /// (txid, height, raw 80-byte header hex) served by get_history /
        /// blockchain.block.header once the test has mined the block.
        confirmed: Option<(String, u32, String)>,
    }

    impl MockElectrum {
        fn spawn() -> Self {
            let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            let addr = listener.local_addr().unwrap();
            let state = Arc::new(Mutex::new(MockElectrumState {
                subscribed: Vec::new(),
                confirmed: None,
            }));
            let clients: Arc<Mutex<Vec<std::sync::mpsc::Sender<String>>>> =
                Arc::new(Mutex::new(Vec::new()));
            {
                let state = state.clone();
                let clients = clients.clone();
                std::thread::spawn(move || {
                    for stream in listener.incoming().flatten() {
                        let (tx, rx) = std::sync::mpsc::channel::<String>();
                        clients.lock().unwrap().push(tx.clone());
                        let mut writer = match stream.try_clone() {
                            Ok(w) => w,
                            Err(_) => continue,
                        };
                        // writer: responses and notifications share the
                        // queue, so per-connection ordering holds
                        std::thread::spawn(move || {
                            use std::io::Write as _;
                            for line in rx {
                                let _ = writeln!(writer, "{line}");
                            }
                        });
                        let state = state.clone();
                        std::thread::spawn(move || {
                            use std::io::BufRead as _;
                            let mut reader = std::io::BufReader::new(stream);
                            let mut line = String::new();
                            while reader.read_line(&mut line).unwrap_or(0) > 0 {
                                if let Ok(req) =
                                    serde_json::from_str::<serde_json::Value>(&line)
                                {
                                    let _ = tx.send(mock_handle_request(&state, &req));
                                }
                                line.clear();
                            }
                            // reader gone: dropping `tx` ends the writer
                        });
                    }
                });
            }
            MockElectrum {
                addr,
                state,
                clients,
            }
        }

        fn subscribed_count(&self) -> usize {
            self.state.lock().unwrap().subscribed.len()
        }

        fn set_confirmed(&self, txid: String, height: u32, header_hex: String) {
            self.state.lock().unwrap().confirmed = Some((txid, height, header_hex));
        }

        /// Pushes a scripthash status notification to every connected
        /// client: the electrum signal that the transaction made it into a
        /// block, driving the tracker into get_history.
        fn notify_subscribed(&self) {
            let shashes = self.state.lock().unwrap().subscribed.clone();
            for shash in shashes {
                let notification = serde_json::json!({
                    "jsonrpc": "2.0",
                    "method": "blockchain.scripthash.subscribe",
                    // 64-hex fake status: sha256 of the new history (the
                    // content itself is never interpreted by the client)
                    "params": [shash, "aa".repeat(32)],
                });
                for client in self.clients.lock().unwrap().iter() {
                    let _ = client.send(notification.to_string());
                }
            }
        }
    }

    fn mock_handle_request(
        state: &Mutex<MockElectrumState>,
        req: &serde_json::Value,
    ) -> String {
        let method = req["method"].as_str().unwrap_or("");
        let result: serde_json::Value = match method {
            // protocol-version negotiation from FrigateClient::connect
            "server.version" => serde_json::json!(["MockElectrum", "1.4"]),
            "blockchain.scripthash.subscribe" => {
                state
                    .lock()
                    .unwrap()
                    .subscribed
                    .push(req["params"][0].as_str().unwrap_or_default().to_string());
                serde_json::Value::Null
            }
            "blockchain.scripthash.get_history" => {
                let guard = state.lock().unwrap();
                match &guard.confirmed {
                    Some((txid, height, _)) => {
                        serde_json::json!([{ "tx_hash": txid, "height": height }])
                    }
                    None => serde_json::json!([]),
                }
            }
            "blockchain.block.header" => {
                let guard = state.lock().unwrap();
                match &guard.confirmed {
                    Some((_, _, header_hex)) => serde_json::json!(header_hex),
                    None => serde_json::Value::Null,
                }
            }
            _ => serde_json::Value::Null,
        };
        serde_json::json!({ "jsonrpc": "2.0", "id": req["id"].clone(), "result": result })
            .to_string()
    }

    /// Full phase-2→3 pipeline against the live regtest rig: the frigate
    /// monitor delivers the payment as a height<=0 mempool entry → candidate
    /// registered (no wallet state) → the output script is registered by its
    /// scripthash with the regular electrum server → the block is mined →
    /// the electrum status notification (racing the phase-1 Confirmed
    /// re-delivery) creates the wallet state exactly once.
    ///
    /// Rig-only: needs frigate on 127.0.0.1:50002, the regtest bitcoind
    /// datadir, bitcoin-cli on PATH and /tmp/sp-pay (SP_PAY_NO_MINE switch).
    /// Run on the code host with:
    /// `FRIGATE_E2E=1 cargo test -p rust_lib_danawallet e2e_regtest -- --ignored`
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    #[ignore = "regtest rig e2e: FRIGATE_E2E=1 cargo test -p rust_lib_danawallet e2e_regtest -- --ignored"]
    async fn e2e_regtest_mempool_entry_to_electrum_confirmation_state() {
        if std::env::var("FRIGATE_E2E").as_deref() != Ok("1") {
            return;
        }
        use std::process::Command;
        use std::time::Instant;

        // mini logger: surface spdk/frigate-crate `log` output in the test
        struct E2eLogger;
        impl log::Log for E2eLogger {
            fn enabled(&self, m: &log::Metadata) -> bool {
                m.level() <= log::Level::Info
            }
            fn log(&self, r: &log::Record) {
                eprintln!("[e2e-log:{}] {}", r.level(), r.args());
            }
            fn flush(&self) {}
        }
        let _ = log::set_boxed_logger(Box::new(E2eLogger));
        log::set_max_level(log::LevelFilter::Info);

        use spdk_wallet::bitcoin::secp256k1::SecretKey;
        use spdk_wallet::bitcoin::Network;
        use spdk_wallet::client::{SpClient, SpendKey};

        let frigate_url =
            std::env::var("FRIGATE_E2E_URL").unwrap_or_else(|_| "127.0.0.1:50002".into());
        let bitcoind_datadir = std::env::var("FRIGATE_E2E_BITCOIND_DATADIR")
            .unwrap_or_else(|_| "/home/hermes/regtest-frigate/bitcoind".into());
        let sp_pay = std::env::var("FRIGATE_E2E_SP_PAY")
            .unwrap_or_else(|_| "/tmp/sp-pay/target/release/sp-pay".into());
        let rpc_wallet =
            std::env::var("FRIGATE_E2E_RPC_WALLET").unwrap_or_else(|_| "miner".into());

        fn btc_cli(datadir: &str, wallet: &str, args: &[&str]) -> String {
            let out = Command::new("bitcoin-cli")
                .arg("-regtest")
                .arg(format!("-datadir={datadir}"))
                .arg(format!("-rpcwallet={wallet}"))
                .args(args)
                .output()
                .expect("bitcoin-cli runnable");
            assert!(
                out.status.success(),
                "bitcoin-cli {args:?} failed: {}",
                String::from_utf8_lossy(&out.stderr)
            );
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        }

        // Rig hygiene: a prior failed run leaks its NO_MINE payment into
        // the mempool (that run never mines it), which would break this
        // run's single-payment mempool assertion. Mine any leftover off
        // before starting.
        let leftovers: Vec<String> =
            serde_json::from_str(&btc_cli(&bitcoind_datadir, &rpc_wallet, &["getrawmempool"]))
                .unwrap();
        if !leftovers.is_empty() {
            let addr = btc_cli(&bitcoind_datadir, &rpc_wallet, &["getnewaddress"]);
            btc_cli(&bitcoind_datadir, &rpc_wallet, &["generatetoaddress", "1", &addr]);
        }

        // Per-run throwaway keys: the rig chain persists between e2e runs,
        // so earlier runs' payments (fixed keys) would otherwise pollute
        // this run's phase-1 history. xorshift64* seeded from time+pid is
        // plenty for a rig test key.
        fn random_key(seed: &mut u64) -> SecretKey {
            let mut buf = [0u8; 32];
            for chunk in buf.chunks_mut(8) {
                *seed ^= *seed >> 12;
                *seed ^= *seed << 25;
                *seed ^= *seed >> 27;
                let v = seed.wrapping_mul(0x2545_F491_4F6C_DD1D);
                chunk.copy_from_slice(&v.to_be_bytes()[..chunk.len()]);
            }
            SecretKey::from_slice(&buf).expect("valid secret key")
        }
        let mut seed = (std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .subsec_nanos() as u64)
            ^ ((std::process::id() as u64) << 32)
            ^ 0x9E37_79B9_7F4A_7C15;
        let scan_sk = random_key(&mut seed);
        let spend_sk = random_key(&mut seed);
        let client =
            SpClient::new(scan_sk, SpendKey::Secret(spend_sk), Network::Regtest).unwrap();
        let address = client.receiving_code().to_string();

        let frigate_bin = std::env::var("FRIGATE_E2E_FRIGATE_BIN")
            .unwrap_or_else(|_| "/home/hermes/tools/frigate-1.4.1/frigate/bin/frigate".into());
        let frigate_args: Vec<String> = std::env::var("FRIGATE_E2E_FRIGATE_ARGS")
            .unwrap_or_else(|_| "--dir /home/hermes/.frigate-regtest -n regtest -l INFO".into())
            .split_whitespace()
            .map(str::to_string)
            .collect();
        let frigate_marker = std::env::var("FRIGATE_E2E_FRIGATE_MARKER")
            .unwrap_or_else(|_| "frigate --dir /home/hermes/.frigate-regtest".into());
        let frigate_log = std::env::var("FRIGATE_E2E_FRIGATE_LOG")
            .unwrap_or_else(|_| "/tmp/frigate-e2e.log".into());

        // kill + relaunch + wait-for-port. `marker` matches only the
        // regtest instance (the frigate.service unit cmdline carries no
        // --dir). setsid detaches the rig from the test process group so
        // it survives the test; the log is captured for post-mortem.
        async fn restart_frigate(
            bin: &str,
            args: &[String],
            marker: &str,
            url: &str,
            log_path: &str,
        ) {
            let _ = Command::new("pkill").args(["-f", marker]).output();
            for _ in 0..50 {
                let alive = Command::new("pgrep")
                    .args(["-f", marker])
                    .output()
                    .map(|o| !o.stdout.is_empty())
                    .unwrap_or(false);
                if !alive {
                    break;
                }
                std::thread::sleep(Duration::from_millis(200));
            }
            let log_file = std::fs::File::create(log_path).expect("frigate log file");
            let log_err = log_file.try_clone().expect("frigate log clone");
            let child = Command::new("setsid")
                .arg(bin)
                .args(args)
                .stdout(std::process::Stdio::from(log_file))
                .stderr(std::process::Stdio::from(log_err))
                .spawn()
                .expect("frigate restart");
            std::mem::forget(child);
            let mut up = false;
            for _ in 0..150 {
                if tokio::net::TcpStream::connect(url).await.is_ok() {
                    up = true;
                    break;
                }
                tokio::time::sleep(Duration::from_millis(500)).await;
            }
            assert!(up, "frigate did not come back on {url}");
            tokio::time::sleep(Duration::from_secs(2)).await;
        }

        // bootstrap: the rig must be reachable before the initial probe
        // (a prior run rig dies with that run process group)
        if tokio::net::TcpStream::connect(&frigate_url).await.is_err() {
            eprintln!("[e2e] rig down at bootstrap; starting it");
            restart_frigate(
                &frigate_bin,
                &frigate_args,
                &frigate_marker,
                &frigate_url,
                &frigate_log,
            )
            .await;
        }

        // Chain tip before anything happens: the monitor subscribes from
        // the tip after the payment, so the mined block lands above it.
        let probe = FrigateClient::connect(&frigate_url, None).await.unwrap();
        let (tip_height, _tip_hash) = probe.block_height().await.unwrap();
        let tip = tip_height.to_consensus_u32();
        eprintln!("[e2e] subscribe-from tip = {tip}");

        // phase 2: the payment enters the mempool and STAYS there
        // (SP_PAY_NO_MINE=1: this test mines the confirming block itself,
        // preserving a real mempool window for the height<=0 entry)
        let out = Command::new(&sp_pay)
            .args([&address, "0.0001"])
            .env("SP_PAY_NO_MINE", "1")
            .output()
            .expect("sp-pay runnable");
        assert!(
            out.status.success(),
            "sp-pay failed: {} {}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
        eprintln!("[e2e] sp-pay: {}", String::from_utf8_lossy(&out.stdout).trim());

        // frigate 1.4.1 does NOT push new mempool entries to a held
        // subscription, and it indexes mempool transactions ONLY at
        // startup (empirical 2026-11-11: a running instance polls new
        // blocks every ~35s but never re-scans the mempool - a payment
        // broadcast after startup is never indexed and never shows up in
        // a subscribe response). The rig is therefore restarted AFTER the
        // payment enters the mempool so the startup index picks it up.
        // Mempool entries (height <= 0) reach the client only in the
        // silentpayments SUBSCRIBE RESPONSE - so keep re-subscribing
        // until the indexed entry comes back as an Unconfirmed event.
        // Each attempt gets a fresh pump/monitor/tracker; earlier
        // attempts created no state and are aborted cleanly.
        restart_frigate(
            &frigate_bin,
            &frigate_args,
            &frigate_marker,
            &frigate_url,
            &frigate_log,
        )
        .await;
        // the initial probe connection died with the killed instance;
        // reconnect once to confirm the restarted instance is serving
        let _reconnect = FrigateClient::connect(&frigate_url, None).await.unwrap();

        let mempool_now: Vec<String> = serde_json::from_str(&btc_cli(
            &bitcoind_datadir,
            &rpc_wallet,
            &["getrawmempool"],
        ))
        .unwrap();
        eprintln!("[e2e] mempool before subscribe loop: {mempool_now:?}");

        let mock = MockElectrum::spawn();
        let start = Instant::now();
        let mut attempt = 0u32;
        let (_monitor_task, pump, sink) = loop {
            attempt += 1;
            assert!(
                attempt <= 15,
                "frigate never delivered the mempool entry via subscribe ({} attempts, {:.0}s)",
                attempt,
                start.elapsed().as_secs_f32()
            );
            let sink = RecordingSink::default();
            let pump = Arc::new(Mutex::new(SyncUpdatePump::with_sink(
                0,
                Box::new(sink.clone()),
            )));
            let scanner = FrigateScanner::new(
                frigate_url.clone(),
                client.scan_key(),
                client.receiver(),
                None,
                HashMap::new(),
            )
            .await
            .unwrap();
            let handle = scanner.start(tip_height);
            let monitor_task =
                tokio::spawn(run_monitor(handle, pump.clone(), mock.addr.to_string()));

            // the subscribe response has ~20s to carry the mempool entry
            let got = tokio::time::timeout(Duration::from_secs(20), async {
                loop {
                    if pump.lock().unwrap().mempool_candidate_count() > 0 {
                        break;
                    }
                    tokio::time::sleep(Duration::from_millis(500)).await;
                }
            })
            .await;
            if got.is_ok() {
                eprintln!(
                    "[e2e] attempt {attempt}: mempool candidate delivered in {:.0}s",
                    start.elapsed().as_secs_f32()
                );
                break (monitor_task, pump, sink);
            }
            eprintln!(
                "[e2e] attempt {attempt}: no mempool candidate ({:.0}s); pump candidates={}, sink updates={}",
                start.elapsed().as_secs_f32(),
                pump.lock().unwrap().mempool_candidate_count(),
                sink.updates.lock().unwrap().len()
            );
            // abort the monitor: dropping it ends the scanner worker and
            // closes the registration channel, so the tracker task exits
            monitor_task.abort();
        };
        assert!(
            sink.updates.lock().unwrap().is_empty(),
            "candidate registration must not create wallet state"
        );

        // the phase-3 tracker must have registered the candidate
        // scripthash with the regular electrum server
        let deadline = Instant::now() + Duration::from_secs(60);
        loop {
            if mock.subscribed_count() > 0 {
                break;
            }
            assert!(
                Instant::now() < deadline,
                "tracker never registered the candidate scripthash with the electrum server"
            );
            tokio::time::sleep(Duration::from_millis(500)).await;
        }

        // the mempool now holds exactly the SP payment: its txid is the
        // candidate the electrum server will report as mined
        let mempool: Vec<String> = serde_json::from_str(&btc_cli(
            &bitcoind_datadir,
            &rpc_wallet,
            &["getrawmempool"],
        ))
        .unwrap();
        assert_eq!(mempool.len(), 1, "expected only the SP payment in mempool");
        let sp_txid = mempool[0].clone();

        // mine the confirming block
        // frigate's height is eventually consistent (it polls new blocks
        // every ~35s), and the hygiene sweep + the funding mine can both
        // land between two polls — so the authoritative pre-mine tip
        // comes from bitcoind, not from frigate.
        let pre_mine_tip: u32 =
            serde_json::from_str(&btc_cli(&bitcoind_datadir, &rpc_wallet, &["getblockcount"]))
                .unwrap();
        assert!(
            pre_mine_tip > tip,
            "sp-pay must have mined at least its funding block (subscribe tip {tip}, pre-mine tip {pre_mine_tip})"
        );
        let mining_addr = btc_cli(&bitcoind_datadir, &rpc_wallet, &["getnewaddress"]);
        let blocks: Vec<String> = serde_json::from_str(&btc_cli(
            &bitcoind_datadir,
            &rpc_wallet,
            &["generatetoaddress", "1", &mining_addr],
        ))
        .unwrap();
        let mined_height = pre_mine_tip + 1;
        // raw block hex: the first 80 bytes are the header the mock serves.
        // This rig bitcoin-cli prints verbosity-0 results as a BARE hex
        // string (no JSON quotes), so no serde parse here.
        let block_hex: String =
            btc_cli(&bitcoind_datadir, &rpc_wallet, &["getblock", &blocks[0], "0"]);
        let header_hex = block_hex[..160].to_string();

        // phase 3: the electrum server reports the mined block for the
        // watched scripthash (status notification -> get_history ->
        // block.header), racing the phase-1 Confirmed re-delivery
        mock.set_confirmed(sp_txid, mined_height, header_hex);
        mock.notify_subscribed();

        // the confirmation (whichever leg wins the race) creates the state
        // exactly once
        let deadline = Instant::now() + Duration::from_secs(180);
        let (conf_count, conf_height, conf_outputs) = loop {
            let guard = sink.updates.lock().unwrap();
            let with_outputs: Vec<&crate::api::structs::state_update::StateUpdate> = guard
                .iter()
                .filter(|u| !u.found_outputs.is_empty())
                .collect();
            if !with_outputs.is_empty() {
                let first = with_outputs[0];
                break (
                    with_outputs.len(),
                    first.blkheight,
                    first.found_outputs.len(),
                );
            }
            drop(guard);
            assert!(
                Instant::now() < deadline,
                "no confirmation state update within budget"
            );
            tokio::time::sleep(Duration::from_millis(500)).await;
        };

        assert_eq!(
            conf_count, 1,
            "the confirmation must create wallet state exactly once"
        );
        assert_eq!(
            conf_height, mined_height,
            "candidate state carries the mined height, never a mempool sentinel"
        );
        assert_eq!(conf_outputs, 1);
        assert_eq!(
            pump.lock().unwrap().emitted_output_count(),
            1,
            "exact-once across the electrum notification and the phase-1 re-report"
        );
    }
}
