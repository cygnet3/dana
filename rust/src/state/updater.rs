use std::{
    collections::{HashMap, HashSet},
    time::{Duration, Instant},
};

use anyhow::Result;
use spdk_wallet::{
    bitcoin::{absolute::Height, BlockHash, OutPoint},
    scanner::{DiscoveredOutput, ScanResult},
};

use crate::api::structs::owned_output::OwnedOutput;
use crate::api::structs::state_update::StateUpdate;
use crate::stream::{send_sync_progress, send_sync_update};

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
}

impl SyncUpdatePump {
    pub fn new(dust_limit: u64) -> Self {
        Self {
            last_update: Instant::now(),
            dust_limit,
            last_height: 0,
            last_hash: String::new(),
            pending_spends: Vec::new(),
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
            send_sync_progress(height);
        }

        Ok(())
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

        send_sync_update(update)?;

        self.last_height = height;
        self.last_hash = hash;
        self.last_update = Instant::now();

        Ok(())
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
}
