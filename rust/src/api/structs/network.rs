use serde::{Deserialize, Serialize};
use spdk_core::bitcoin;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ApiNetwork {
    Mainnet,
    Testnet3,
    Testnet4,
    Signet,
    Regtest,
}

impl From<spdk_core::bitcoin::Network> for ApiNetwork {
    fn from(value: spdk_core::bitcoin::Network) -> Self {
        match value {
            bitcoin::Network::Bitcoin => ApiNetwork::Mainnet,
            bitcoin::Network::Testnet => ApiNetwork::Testnet3,
            bitcoin::Network::Testnet4 => ApiNetwork::Testnet4,
            bitcoin::Network::Signet => ApiNetwork::Signet,
            bitcoin::Network::Regtest => ApiNetwork::Regtest,
        }
    }
}

impl From<ApiNetwork> for spdk_core::bitcoin::Network {
    fn from(value: ApiNetwork) -> Self {
        match value {
            ApiNetwork::Mainnet => spdk_core::bitcoin::Network::Bitcoin,
            ApiNetwork::Testnet3 => spdk_core::bitcoin::Network::Testnet,
            ApiNetwork::Testnet4 => spdk_core::bitcoin::Network::Testnet4,
            ApiNetwork::Signet => spdk_core::bitcoin::Network::Signet,
            ApiNetwork::Regtest => spdk_core::bitcoin::Network::Regtest,
        }
    }
}
