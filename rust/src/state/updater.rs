use std::{
    collections::{HashMap, HashSet},
    time::{Duration, Instant},
};

use anyhow::Result;
use spdk_wallet::{
    bitcoin::{absolute::Height, BlockHash, OutPoint, Txid},
    scanner::{DiscoveredOutput, ScanResult},
};

use crate::api::structs::owned_output::OwnedOutput;
use crate::api::structs::state_update::StateUpdate;
use crate::stream::{send_sync_progress, send_sync_update};

/// Destination for emitted [`StateUpdate`]s.
///
/// Production sends through the FRB stream sink; tests inject a recorder so
/// the exact-once guarantee (phase-2/3 contract) is observable without a
/// stream registration.
pub trait StateSink: Send {
    fn send(&self, update: StateUpdate) -> anyhow::Result<()>;
}

/// Production sink: the FRB state-update stream.
struct StreamStateSink;

impl StateSink for StreamStateSink {
    fn send(&self, update: StateUpdate) -> anyhow::Result<()> {
        send_sync_update(update)
    }
}

/// Test sink recording every emitted update (shared via Arc so tests can
/// hold the handle while the pump owns the sink).
#[cfg(test)]
#[derive(Clone, Default)]
pub struct RecordingSink {
    pub updates: std::sync::Arc<std::sync::Mutex<Vec<StateUpdate>>>,
}

#[cfg(test)]
impl StateSink for RecordingSink {
    fn send(&self, update: StateUpdate) -> anyhow::Result<()> {
        self.updates.lock().unwrap().push(update);
        Ok(())
    }
}

const MAX_TIME_BETWEEN_UPDATES: Duration = Duration::from_secs(30);

/// Drives scanner results into the Dart state stream.
///
/// Replaces the old spdk `Updater` implementation: spdk's scanners now stream
/// `ScanResult`s (blindbit) / `FrigateEvent`s (frigate), so the consumer owns
/// throttling and persistence signalling.
///
/// Invariant: the emitted `StateUpdate.blkheight` never moves backward. Dart
/// calls `saveLastSync(event.blkheight)` on every update, so an out-of-order
/// height would rewind the wallet's sync checkpoint. Updates whose height is
/// older than the last emitted one are dropped (frigate/blindbit streams are
/// ordered, so this is a pathological-case guard only).
///
/// Early-arrival spends: the frigate scanner surfaces offline spends as
/// `Spent` events during its subscribe-time history sweep, before any block
/// history (`Confirmed`) has been streamed. No real height has been emitted
/// yet at that point, so emitting one would fabricate
/// `StateUpdate { blkheight: 0, blkhash: "" }` — and Dart's
/// `saveLastSync(event.blkheight)` would rewind the wallet checkpoint to 0.
/// Such spends are held in `pending_spends` and flushed as `found_inputs` on
/// the next emit that carries a real height, ahead of that update's own
/// discoveries.
pub struct SyncUpdatePump {
    last_update: Instant,
    dust_limit: u64,
    last_height: u32,
    last_hash: String,
    /// Spends received before any real height was emitted (see struct docs).
    pending_spends: Vec<HashSet<OutPoint>>,
    /// Destination for emitted state updates.
    sink: Box<dyn StateSink>,
    /// Phase-2 (mempool) candidates: txid → outpoints discovered at
    /// height <= 0. Never advances the checkpoint and never touches the
    /// progress bar; the registry is ephemeral per pump instance.
    mempool_candidates: HashMap<Txid, HashSet<OutPoint>>,
    /// Outpoints already emitted as wallet state (candidate path or a
    /// confirmed delivery). Exact-once guard against duplicate state.
    emitted_outputs: HashSet<OutPoint>,
    /// Heights pushed to the progress notifier (test observability).
    #[cfg(test)]
    progress_log: Vec<u32>,
}

impl SyncUpdatePump {
    pub fn new(dust_limit: u64) -> Self {
        Self::with_sink(dust_limit, Box::new(StreamStateSink))
    }

    #[cfg(test)]
    pub fn with_sink(dust_limit: u64, sink: Box<dyn StateSink>) -> Self {
        Self {
            last_update: Instant::now(),
            dust_limit,
            last_height: 0,
            last_hash: String::new(),
            pending_spends: Vec::new(),
            sink,
            mempool_candidates: HashMap::new(),
            emitted_outputs: HashSet::new(),
            progress_log: Vec::new(),
        }
    }

    /// Forward one scanner block result.
    ///
    /// `is_final` must be set for the last block of a bounded scan (blindbit
    /// path), mirroring the old "final update is always sent" behaviour.
    pub fn record(&mut self, scan_result: ScanResult, is_final: bool) -> Result<()> {
        let height = scan_result.blkheight.to_consensus_u32();
        let hash = scan_result.blkhash.to_string();

        // we send a state update in 3 cases:
        // - we have found new spent inputs or discovered outputs
        // - the maximum delay between updates has been reached
        // - we're sending the final update
        let new_discoveries = !scan_result.discovered_inputs.is_empty()
            || !scan_result.discovered_outputs.is_empty();
        let max_delay_reached = self.last_update.elapsed() > MAX_TIME_BETWEEN_UPDATES;

        if new_discoveries || max_delay_reached || is_final {
            self.emit(
                height,
                hash,
                scan_result.discovered_inputs,
                scan_result.discovered_outputs,
            )?;
        } else {
            // whether we update or not, we always notify the progress notifier
            // note: the scan progress notifyer is purely to show scan progress to
            // the user, it does not affect persistent storage
            self.notify_progress(height);
        }

        Ok(())
    }

    /// Register a phase-2 (mempool) discovery: a transaction that entered
    /// the mempool carrying outputs of our scan key (height <= 0 entry over
    /// the key-bearing subscription).
    ///
    /// Contract (decision-record amendment 2026-11-10): the candidate is
    /// registered and tracked, but wallet state is created only on the
    /// confirmation notification (phase 3), the checkpoint is NEVER advanced
    /// and the progress bar is NEVER touched by mempool activity.
    pub fn record_mempool(
        &mut self,
        txid: Txid,
        discovered_outputs: HashMap<OutPoint, DiscoveredOutput>,
    ) -> Result<()> {
        // TDD red state (stub): mempool discoveries are logged and dropped,
        // byte-identical to the pre-phase-2 behavior. The candidate
        // registration is implemented to green in the follow-up commit.
        let _ = (txid, discovered_outputs);
        log::debug!("frigate: mempool discovery deferred (candidate pipeline not wired)");
        Ok(())
    }

    /// Test observability: number of registered mempool candidates.
    #[cfg(test)]
    pub fn mempool_candidate_count(&self) -> usize {
        self.mempool_candidates.len()
    }

    /// Test observability: the last emitted (checkpoint) height.
    #[cfg(test)]
    pub fn last_emitted_height(&self) -> u32 {
        self.last_height
    }

    /// Test observability: heights pushed to the progress notifier.
    #[cfg(test)]
    pub fn progress_log(&self) -> &[u32] {
        &self.progress_log
    }

    /// Test observability: outpoints already emitted as wallet state.
    #[cfg(test)]
    pub fn emitted_output_count(&self) -> usize {
        self.emitted_outputs.len()
    }

    /// Outpoints spent in confirmed transactions (frigate `Spent` events).
    ///
    /// Before any real height has been emitted (`last_height == 0`), the
    /// outpoints are buffered instead of emitted: a `Spent` arriving during
    /// the frigate history sweep would otherwise be published at
    /// `blkheight: 0`, rewinding Dart's sync checkpoint (see struct docs).
    /// After the first real-height update, spends are emitted at the last
    /// emitted height/hash so the checkpoint cannot move backward; the spend
    /// marking itself is keyed by outpoint, not height.
    pub fn record_spent(&mut self, spent: HashSet<OutPoint>) -> Result<()> {
        if spent.is_empty() {
            return Ok(());
        }
        if self.last_height == 0 {
            // No real height emitted yet: stash instead of fabricating a
            // blkheight-0 update; the buffer rides the next real-height emit.
            self.pending_spends.push(spent);
            return Ok(());
        }
        self.emit(
            self.last_height,
            self.last_hash.clone(),
            spent,
            HashMap::new(),
        )?;
        Ok(())
    }

    /// End of a scan phase (blindbit range end / frigate `CaughtUp`): advance
    /// the checkpoint to `height` if it moves forward. Empty update.
    pub fn finalize(&mut self, height: Height, hash: BlockHash) -> Result<()> {
        let height_u32 = height.to_consensus_u32();
        if height_u32 > self.last_height {
            self.emit(height_u32, hash.to_string(), HashSet::new(), HashMap::new())?;
        }
        Ok(())
    }

    fn emit(
        &mut self,
        height: u32,
        hash: String,
        mut discovered_inputs: HashSet<OutPoint>,
        mut discovered_outputs: HashMap<OutPoint, DiscoveredOutput>,
    ) -> Result<()> {
        if height < self.last_height {
            log::warn!(
                "dropping sync update at height {height} (checkpoint already at {})",
                self.last_height
            );
            return Ok(());
        }

        // Flush spends buffered before the first real-height emission: merge
        // them into this update's own found_inputs so they leave the pump in
        // a single StateUpdate carrying a real, monotonic height. The buffer
        // is only ever non-empty while `last_height == 0`, so this fires at
        // most once, on the first forward emit after early `Spent` events.
        if height > 0 && !self.pending_spends.is_empty() {
            for pending in self.pending_spends.drain(..) {
                discovered_inputs.extend(pending);
            }
        }

        // the blindbit backend filters dust server-side; for the frigate
        // scanner we apply the same cut client-side
        discovered_outputs.retain(|_, d| d.txout.value.to_sat() >= self.dust_limit);

        let update = StateUpdate {
            blkheight: height,
            blkhash: hash.clone(),
            found_outputs: discovered_outputs
                .into_iter()
                .map(|(outpoint, output)| OwnedOutput {
                    outpoint: outpoint.into(),
                    tweak: output.tweak.to_be_bytes(),
                    amount: output.txout.value.into(),
                    script: output.txout.script_pubkey.to_bytes(),
                    label: output.label.map(|l| l.as_inner().to_be_bytes()),
                })
                .collect(),
            found_inputs: discovered_inputs
                .into_iter()
                .map(|outpoint| outpoint.into())
                .collect(),
        };

        self.sink.send(update)?;

        self.last_height = height;
        self.last_hash = hash;
        self.last_update = Instant::now();

        Ok(())
    }

    /// Push a scan-progress height to the notifier (test-observed via
    /// [`Self::progress_log`]).
    fn notify_progress(&mut self, height: u32) {
        #[cfg(test)]
        self.progress_log.push(height);
        send_sync_progress(height);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use spdk_wallet::bitcoin::Txid;
    use std::str::FromStr;

    fn outpoint(v: u8) -> OutPoint {
        OutPoint::new(Txid::from_str(&format!("{v:064x}")).unwrap(), 0)
    }

    fn scan_result(height: u32) -> ScanResult {
        ScanResult {
            blkheight: Height::from_consensus(height).unwrap(),
            blkhash: BlockHash::from_str(
                "0000000000000000000000000000000000000000000000000000000000000000",
            )
            .unwrap(),
            discovered_inputs: HashSet::new(),
            discovered_outputs: HashMap::new(),
        }
    }

    /// A `Spent` arriving before any real height is buffered, never emitted.
    /// With no stream sink registered any attempted emission fails with
    /// "Stream sink not available", so `record_spent` returning `Ok(())`
    /// proves no emission — in particular no blkheight-0 update — was
    /// attempted (the pre-fix behavior).
    #[test]
    fn spent_before_first_height_is_buffered() {
        let mut pump = SyncUpdatePump::new(0);
        pump.record_spent(HashSet::from([outpoint(1)])).unwrap();
        assert_eq!(pump.pending_spends.len(), 1);
        assert!(pump.pending_spends[0].contains(&outpoint(1)));
    }

    /// The buffered spend flushes on the next real-height emission
    /// (is_final=true forces the emit) and the buffer is consumed. The
    /// no-sink error proves an emission was attempted for the real height
    /// rather than the buffered spend being silently dropped.
    #[test]
    fn pending_spends_flush_on_next_real_height_emit() {
        let mut pump = SyncUpdatePump::new(0);
        pump.record_spent(HashSet::from([outpoint(1)])).unwrap();
        let err = pump
            .record(scan_result(800_001), true)
            .expect_err("no stream sink registered: real-height emit must be attempted");
        assert!(err.to_string().contains("Stream sink not available"));
        assert!(pump.pending_spends.is_empty());
    }

    /// Checkpoint monotonicity (D10 acceptance): an emit whose height is
    /// older than the last emitted one is dropped — `Ok(())`, no emission,
    /// `last_height` unchanged — even when the update carries discoveries.
    /// Dart persists `saveLastSync(event.blkheight)` for every emitted
    /// update, so this guard is what keeps the persisted checkpoint from
    /// ever moving backward.
    #[test]
    fn out_of_order_height_is_dropped() {
        let mut pump = SyncUpdatePump::new(0);
        pump.last_height = 800_002;
        pump.last_hash = "h".to_string();
        let mut older = scan_result(800_001);
        older.discovered_inputs.insert(outpoint(1));
        pump.record(older, false).unwrap();
        assert_eq!(pump.last_height, 800_002);
    }

    /// Checkpoint monotonicity: `finalize` (frigate `CaughtUp` / blindbit
    /// range end) never moves the checkpoint backward. A tip older than the
    /// last emitted height is ignored without attempting an emission — the
    /// absence of the no-sink emission error proves that.
    #[test]
    fn finalize_never_rewinds_checkpoint() {
        let mut pump = SyncUpdatePump::new(0);
        pump.last_height = 800_002;
        pump.last_hash = "h".to_string();
        pump.finalize(
            Height::from_consensus(800_001).unwrap(),
            BlockHash::from_str(&"0".repeat(64)).unwrap(),
        )
        .unwrap();
        assert_eq!(pump.last_height, 800_002);
    }
}
