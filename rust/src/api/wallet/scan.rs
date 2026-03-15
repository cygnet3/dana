use std::{collections::HashSet, str::FromStr};

use anyhow::Result;
use spdk_wallet::backend_blindbit_v1::{BlindbitBackend, BlindbitClient};
use spdk_wallet::bitcoin::{Amount, absolute::Height, OutPoint};
use spdk_wallet::scanner::SpScanner;

use crate::{state::StateUpdater, wallet::KEEP_SCANNING};

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
        owned_outpoints: Vec<String>,
    ) -> Result<()> {
        let client = BlindbitClient::new(&blindbit_url)?;
        let backend = BlindbitBackend::new(client);

        let dust_limit = Amount::from_sat(dust_limit);

        let owned_outpoints: HashSet<OutPoint> = owned_outpoints
            .into_iter()
            .map(|s| OutPoint::from_str(&s))
            .collect::<Result<_, _>>()?;

        let start = Height::from_consensus(from_height)?;
        let end = Height::from_consensus(to_height)?;

        let sp_client = self.client.clone();
        let updater = StateUpdater::new(end);

        KEEP_SCANNING.store(true, std::sync::atomic::Ordering::Relaxed);

        let mut scanner = SpScanner::new(
            sp_client,
            Box::new(updater),
            Box::new(backend),
            owned_outpoints,
            &KEEP_SCANNING,
        );

        scanner
            .scan_blocks(start, end, dust_limit, ENABLE_CUTTHROUGH)
            .await?;

        Ok(())
    }
}
