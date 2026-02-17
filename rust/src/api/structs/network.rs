use serde::{Deserialize, Serialize};
use spdk_core::bitcoin;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Network {
    Mainnet,
    Testnet3,
    Testnet4,
    Signet,
    Regtest,
}

impl From<spdk_core::bitcoin::Network> for Network {
    fn from(value: spdk_core::bitcoin::Network) -> Self {
        match value {
            bitcoin::Network::Bitcoin => Network::Mainnet,
            bitcoin::Network::Testnet => Network::Testnet3,
            bitcoin::Network::Testnet4 => Network::Testnet4,
            bitcoin::Network::Signet => Network::Signet,
            bitcoin::Network::Regtest => Network::Regtest,
        }
    }
}

impl From<Network> for spdk_core::bitcoin::Network {
    fn from(value: Network) -> Self {
        match value {
            Network::Mainnet => spdk_core::bitcoin::Network::Bitcoin,
            Network::Testnet3 => spdk_core::bitcoin::Network::Testnet,
            Network::Testnet4 => spdk_core::bitcoin::Network::Testnet4,
            Network::Signet => spdk_core::bitcoin::Network::Signet,
            Network::Regtest => spdk_core::bitcoin::Network::Regtest,
        }
    }
}
