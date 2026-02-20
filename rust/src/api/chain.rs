use std::time::Duration;

use log::warn;
use spdk_wallet::backend_blindbit_v1::{BlindbitBackend, BlindbitClient};
use spdk_wallet::bitcoin;
use spdk_wallet::chain::ChainBackend;
use tokio::time::sleep;

use crate::api::structs::network::ApiNetwork;

pub async fn get_chain_height(blindbit_url: String) -> anyhow::Result<u32> {
    let backend = BlindbitBackend::new(blindbit_url)?;

    match backend.block_height().await {
        Ok(res) => Ok(res.to_consensus_u32()),
        Err(e) => {
            if e.root_cause()
                .to_string()
                .starts_with("operation timed out")
            {
                warn!("Got timeout fetching block height, retrying");

                // sleep for 1 second
                sleep(Duration::from_millis(1000)).await;

                Ok(backend.block_height().await?.to_consensus_u32())
            } else {
                Err(e)
            }
        }
    }
}

pub async fn check_network(blindbit_url: String, network: ApiNetwork) -> anyhow::Result<bool> {
    let network: bitcoin::Network = network.into();
    let client = BlindbitClient::new(blindbit_url)?;

    let blindbit_network = client.info().await?.network;

    Ok(network == blindbit_network)
}
