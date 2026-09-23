use std::collections::HashSet;
use std::time::{Duration, Instant};

use anyhow::Result;
use futures::StreamExt as _;
use spdk_wallet::backend_blindbit_v1::{BlindbitBackend, BlindbitClient};
use spdk_wallet::bitcoin::{absolute::Height, Amount};
use spdk_wallet::scanner::{ScanResult, Scanner as _};
use spdk_wallet::SpScanner;

use crate::api::structs::outpoint::OutPoint;
use crate::api::structs::owned_output::OwnedOutput;
use crate::api::structs::state_update::StateUpdate;
use crate::stream::{send_sync_progress, send_sync_update};
use crate::wallet::KEEP_SYNCING;

use super::SpWallet;

/// we enable cutthrough by default, no need to let the user decide
const ENABLE_CUTTHROUGH: bool = true;

const MAX_TIME_BETWEEN_UPDATES: Duration = Duration::from_secs(30);

impl SpWallet {
    #[flutter_rust_bridge::frb(sync)]
    pub fn interrupt_sync() {
        KEEP_SYNCING.store(false, std::sync::atomic::Ordering::Relaxed);
    }

    pub async fn sync_to_height(
        &self,
        from_height: u32,
        to_height: u32,
        blindbit_url: String,
        dust_limit: u64,
        owned_outpoints: Vec<OutPoint>,
    ) -> Result<()> {
        let client = BlindbitClient::new(&blindbit_url)?;
        let backend = BlindbitBackend::new(client);

        let dust_limit = Amount::from_sat(dust_limit);

        let owned_outpoints: HashSet<spdk_wallet::bitcoin::OutPoint> =
            owned_outpoints.into_iter().map(Into::into).collect();

        let start = Height::from_consensus(from_height)?;
        let end = Height::from_consensus(to_height)?;

        let b_scan = self.get_scan_key().into();
        let sp_receiver = self.client.receiver();

        KEEP_SYNCING.store(true, std::sync::atomic::Ordering::Relaxed);

        let scanner = SpScanner::new(
            Box::new(backend),
            b_scan,
            sp_receiver,
            owned_outpoints,
            dust_limit,
            ENABLE_CUTTHROUGH,
            &KEEP_SYNCING,
        );

        let mut rx = scanner.scan_blocks(start..=end);

        let mut last_update = Instant::now();
        while let Some(update) = rx.next().await {
            record_block_scan_result(update, &mut last_update, end)?;
        }

        Ok(())
    }
}

fn record_block_scan_result(
    update: ScanResult,
    last_update: &mut Instant,
    final_update_height: Height,
) -> Result<()> {
    let ScanResult {
        blkheight,
        blkhash,
        discovered_inputs,
        discovered_outputs,
    } = update;

    // we send a state update in 3 cases:
    // - we have found new spent inputs or discovered outputs
    // - the maximum delay between updates has been reached
    // - we're sending the final update
    let new_discoveries = !discovered_inputs.is_empty() || !discovered_outputs.is_empty();
    let is_final_block_update = blkheight == final_update_height;
    let max_delay_reached = last_update.elapsed() > MAX_TIME_BETWEEN_UPDATES;

    if new_discoveries || is_final_block_update || max_delay_reached {
        // sending a state update always implies we are writing to persistent storage
        let update = StateUpdate {
            blkheight: blkheight.to_consensus_u32(),
            blkhash: blkhash.to_string(),
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

        *last_update = Instant::now();
    }

    // whether we update or not, we always notify the progress notifier
    // note: the scan progress notifyer is purely to show scan progress to the user,
    // it does not affect persistent storage
    send_sync_progress(blkheight.to_consensus_u32());

    Ok(())
}
