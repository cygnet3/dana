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
pub struct SyncUpdatePump {
    last_update: Instant,
    dust_limit: u64,
    last_height: u32,
    last_hash: String,
}

impl SyncUpdatePump {
    pub fn new(dust_limit: u64) -> Self {
        Self {
            last_update: Instant::now(),
            dust_limit,
            last_height: 0,
            last_hash: String::new(),
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
    /// Emitted at the last emitted height/hash so the checkpoint cannot move
    /// backward; the spend marking itself is keyed by outpoint, not height.
    pub fn record_spent(&mut self, spent: HashSet<OutPoint>) -> Result<()> {
        if spent.is_empty() {
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
        discovered_inputs: HashSet<OutPoint>,
        mut discovered_outputs: HashMap<OutPoint, DiscoveredOutput>,
    ) -> Result<()> {
        if height < self.last_height {
            log::warn!(
                "dropping sync update at height {height} (checkpoint already at {})",
                self.last_height
            );
            return Ok(());
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
