mod info;
pub mod setup;
mod sync;
pub mod transaction;
pub mod coin_selection;

use crate::api::structs::network::Network;
use anyhow::Result;
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin::bip32;
use spdk_wallet::bitcoin::secp256k1::SecretKey;
use spdk_wallet::client::{SpClient, SpendKey};

#[derive(Debug, Clone)]
#[frb(opaque)]
pub struct SpWallet {
    client: SpClient,
    fingerprint: Option<bip32::Fingerprint>,
    derivation_path: Option<bip32::DerivationPath>,
}

impl SpWallet {
    #[frb(sync)]
    pub fn new(
        scan_key: ApiScanKey,
        spend_key: ApiSpendKey,
        network: Network,
        fingerprint: Option<Fingerprint>,
        derivation_path: Option<DerivationPath>,
    ) -> Result<Self> {
        let client = SpClient::new(scan_key.into(), spend_key.into(), network.into())?;

        Ok(Self {
            client,
            fingerprint: fingerprint.map(Into::into),
            derivation_path: derivation_path.map(Into::into),
        })
    }

    #[frb(sync)]
    pub fn get_scan_key(&self) -> ApiScanKey {
        ApiScanKey(self.client.get_scan_key())
    }

    #[frb(sync)]
    pub fn get_spend_key(&self) -> ApiSpendKey {
        ApiSpendKey(self.client.get_spend_key())
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiScanKey(pub(crate) SecretKey);

impl ApiScanKey {
    #[frb(sync)]
    pub fn decode(encoded: String) -> Result<Self> {
        Ok(serde_json::from_str(&encoded)?)
    }

    #[frb(sync)]
    pub fn encode(&self) -> Result<String> {
        Ok(serde_json::to_string(&self)?)
    }
}

impl From<ApiScanKey> for SecretKey {
    fn from(scan_key: ApiScanKey) -> Self {
        scan_key.0
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiSpendKey(pub(crate) SpendKey);

impl ApiSpendKey {
    #[frb(sync)]
    pub fn decode(encoded: String) -> Result<Self> {
        Ok(serde_json::from_str(&encoded)?)
    }

    #[frb(sync)]
    pub fn encode(&self) -> Result<String> {
        Ok(serde_json::to_string(&self)?)
    }
}

impl From<ApiSpendKey> for SpendKey {
    fn from(spend_key: ApiSpendKey) -> Self {
        spend_key.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Fingerprint(pub String);

impl From<bip32::Fingerprint> for Fingerprint {
    fn from(value: bip32::Fingerprint) -> Self {
        Self(value.to_string())
    }
}

impl From<Fingerprint> for bip32::Fingerprint {
    fn from(value: Fingerprint) -> Self {
        value.0.parse().expect("invalid fingerprint hex")
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DerivationPath(pub String);

impl From<bip32::DerivationPath> for DerivationPath {
    fn from(value: bip32::DerivationPath) -> Self {
        Self(value.to_string())
    }
}

impl From<DerivationPath> for bip32::DerivationPath {
    fn from(value: DerivationPath) -> Self {
        value.0.parse().expect("invalid derivation path")
    }
}
