use std::collections::HashSet;

use anyhow::Result;
use futures::StreamExt as _;
use spdk_wallet::backend_blindbit_v1::BlindbitBackend;
use spdk_wallet::bitcoin::{absolute::Height, Amount};
use spdk_wallet::SpScanner;
use spdk_wallet::scanner::Scanner;

use crate::api::structs::outpoint::OutPoint;
use crate::state::SyncUpdatePump;
use crate::wallet::KEEP_SYNCING;

use super::SpWallet;

/// we enable cutthrough by default, no need to let the user decide
const ENABLE_CUTTHROUGH: bool = true;

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
        let backend = BlindbitBackend::new(&blindbit_url)?;

        let dust_limit = Amount::from_sat(dust_limit);

        let owned_outpoints: HashSet<spdk_wallet::bitcoin::OutPoint> =
            owned_outpoints.into_iter().map(Into::into).collect();

        let start = Height::from_consensus(from_height)?;
        let end = Height::from_consensus(to_height)?;

        let scan_key = self.client.scan_key();
        let sp_receiver = self.client.receiver();

        KEEP_SYNCING.store(true, std::sync::atomic::Ordering::Relaxed);

        let scanner = SpScanner::new(
            Box::new(backend),
            scan_key,
            sp_receiver,
            owned_outpoints,
            dust_limit,
            ENABLE_CUTTHROUGH,
            &KEEP_SYNCING,
        );

        let mut results = scanner.scan_blocks(start..=end);
        let mut pump = SyncUpdatePump::new(dust_limit.to_sat());

        while let Some(scan_result) = results.next().await {
            let is_final = scan_result.blkheight >= end;
            pump.record(scan_result, is_final)?;
        }

        Ok(())
    }
}
