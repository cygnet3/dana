use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ApiNetwork {
    Mainnet,
    Testnet3,
    Testnet4,
    Signet,
    Regtest,
}

impl From<bitcoin::Network> for ApiNetwork {
    fn from(value: bitcoin::Network) -> Self {
        match value {
            bitcoin::Network::Bitcoin => ApiNetwork::Mainnet,
            bitcoin::Network::Testnet => ApiNetwork::Testnet3,
            bitcoin::Network::Testnet4 => ApiNetwork::Testnet4,
            bitcoin::Network::Signet => ApiNetwork::Signet,
            bitcoin::Network::Regtest => ApiNetwork::Regtest,
        }
    }
}

impl From<ApiNetwork> for bitcoin::Network {
    fn from(value: ApiNetwork) -> Self {
        match value {
            ApiNetwork::Mainnet => bitcoin::Network::Bitcoin,
            ApiNetwork::Testnet3 => bitcoin::Network::Testnet,
            ApiNetwork::Testnet4 => bitcoin::Network::Testnet4,
            ApiNetwork::Signet => bitcoin::Network::Signet,
            ApiNetwork::Regtest => bitcoin::Network::Regtest,
        }
    }
}
