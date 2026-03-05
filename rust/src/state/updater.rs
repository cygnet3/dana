use std::{
    collections::{HashMap, HashSet},
    time::{Duration, Instant},
};

use spdk_wallet::updater::Updater;
use spdk_wallet::{
    bitcoin::{absolute::Height, BlockHash, OutPoint},
    updater::DiscoveredOutput,
};

use crate::stream::{send_sync_progress, send_sync_update, StateUpdate};

use anyhow::Result;

const MAX_TIME_BETWEEN_UPDATES: Duration = Duration::from_secs(30);

pub struct StateUpdater {
    last_update: Instant,
    final_update_height: Height,
}

impl StateUpdater {
    pub fn new(final_update_height: Height) -> Self {
        Self {
            last_update: Instant::now(),
            final_update_height,
        }
    }
}

impl Updater for StateUpdater {
    fn record_block_scan_result(
        &mut self,
        blkheight: Height,
        blkhash: BlockHash,
        discovered_inputs: HashSet<OutPoint>,
        discovered_outputs: HashMap<OutPoint, DiscoveredOutput>,
    ) -> Result<()> {
        // we send a state update in 3 cases:
        // - we have found new spent inputs or discovered outputs
        // - the maximum delay between updates has been reached
        // - we're sending the final update
        let new_discoveries = !discovered_inputs.is_empty() || !discovered_outputs.is_empty();
        let is_final_block_update = blkheight == self.final_update_height;
        let max_delay_reached = self.last_update.elapsed() > MAX_TIME_BETWEEN_UPDATES;

        if new_discoveries || is_final_block_update || max_delay_reached {
            // sending a state update always implies we are writing to persistent storage
            let update = StateUpdate {
                blkheight,
                blkhash,
                found_outputs: discovered_outputs,
                found_inputs: discovered_inputs,
            };

            send_sync_update(update);

            self.last_update = Instant::now();
        }

        // whether we update or not, we always notify the progress notifier
        // note: the scan progress notifyer is purely to show scan progress to the user,
        // it does not affect persistent storage
        send_sync_progress(blkheight.to_consensus_u32());

        Ok(())
    }
}
