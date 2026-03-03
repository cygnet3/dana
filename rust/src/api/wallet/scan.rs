use anyhow::Result;
use spdk_wallet::backend_blindbit_v1::{BlindbitBackend, BlindbitClient};
use spdk_wallet::bitcoin::absolute::Height;
use spdk_wallet::bitcoin::Amount;
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

    pub async fn sync_to_height(
        &self,
        from_height: u32,
        to_height: u32,
        blindbit_url: String,
        dust_limit: u64,
        owned_outpoints: OwnedOutPoints,
    ) -> Result<()> {
        let client = BlindbitClient::new(&blindbit_url)?;
        let backend = BlindbitBackend::new(client);

        let dust_limit = Amount::from_sat(dust_limit);

        let start = Height::from_consensus(from_height)?;
        let end = Height::from_consensus(to_height)?;

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
