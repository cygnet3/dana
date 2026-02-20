use anyhow::Result;
use spdk_wallet::backend_blindbit_v1::BlindbitBackend;
use spdk_wallet::bitcoin;
use spdk_wallet::chain::ChainBackend;
use spdk_wallet::scanner::SpScanner;

use crate::{api::outputs::OwnedOutPoints, state::StateUpdater, wallet::KEEP_SCANNING};

use super::SpWallet;

/// we enable cutthrough by default, no need to let the user decide
const ENABLE_CUTTHROUGH: bool = true;

impl SpWallet {
    #[flutter_rust_bridge::frb(sync)]
    pub fn interrupt_scanning() {
        KEEP_SCANNING.store(false, std::sync::atomic::Ordering::Relaxed);
    }

    pub async fn scan_to_tip(
        &self,
        blindbit_url: String,
        last_scan: u32,
        dust_limit: u64,
        owned_outpoints: OwnedOutPoints,
    ) -> Result<()> {
        let backend = BlindbitBackend::new(blindbit_url)?;

        let dust_limit = bitcoin::Amount::from_sat(dust_limit);

        let start = bitcoin::absolute::Height::from_consensus(last_scan + 1)?;
        let end = backend.block_height().await?;

        let sp_client = self.client.clone();
        let updater = StateUpdater::new();

        KEEP_SCANNING.store(true, std::sync::atomic::Ordering::Relaxed);

        let mut scanner = SpScanner::new(
            sp_client,
            Box::new(updater),
            Box::new(backend),
            owned_outpoints.to_inner(),
            &KEEP_SCANNING,
        );

        scanner
            .scan_blocks(start, end, dust_limit, ENABLE_CUTTHROUGH)
            .await?;

        Ok(())
    }
}
