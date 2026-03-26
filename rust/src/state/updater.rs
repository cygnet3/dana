use std::{
    collections::{HashMap, HashSet},
    time::{Duration, Instant},
};

use spdk_wallet::updater::Updater;
use spdk_wallet::{
    bitcoin::{absolute::Height, BlockHash, OutPoint},
    updater::DiscoveredOutput,
};

use crate::{
    api::structs::sync_queue_item::SyncQueueItem,
    stream::{send_sync_progress, send_sync_update, StateUpdate},
};

use anyhow::Result;

const MAX_TIME_BETWEEN_UPDATES: Duration = Duration::from_secs(5);

pub struct StateUpdater {
    last_update: Instant,
    item: SyncQueueItem,
}

impl StateUpdater {
    pub fn new(item: SyncQueueItem) -> Self {
        Self {
            last_update: Instant::now(),
            item,
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
        let is_final_block_update = blkheight.to_consensus_u32() == self.item.start;
        let max_delay_reached = self.last_update.elapsed() > MAX_TIME_BETWEEN_UPDATES;

        if new_discoveries || is_final_block_update || max_delay_reached {
            // sending a state update always implies we are writing to persistent storage
            let update = StateUpdate {
                queue_item_id: self.item.id,
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
