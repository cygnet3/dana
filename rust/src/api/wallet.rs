pub mod coin_selection;
mod info;
pub mod setup;
mod sync;
pub mod transaction;

use crate::api::structs::network::Network;
use anyhow::{anyhow, Result};
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
            fingerprint: fingerprint
                .map(|f| f.0.parse())
                .transpose()
                .map_err(|e| anyhow!("invalid fingerprint: {e}"))?,
            derivation_path: derivation_path
                .map(|p| p.0.parse())
                .transpose()
                .map_err(|e| anyhow!("invalid derivation path: {e}"))?,
        })
    }

    #[frb(sync)]
    pub fn get_scan_key(&self) -> ApiScanKey {
        ApiScanKey(self.client.scan_key())
    }

    #[frb(sync)]
    pub fn get_spend_key(&self) -> ApiSpendKey {
        ApiSpendKey(self.client.spend_key())
    }

    /// BIP-32 key origin written into PSBT inputs for this wallet.
    ///
    /// Unknown origin (imported keys, no seed) is encoded as a zero
    /// fingerprint and an empty path, matching the previous PSBT flow.
    pub(crate) fn psbt_key_source(&self) -> Result<(bip32::Fingerprint, bip32::DerivationPath)> {
        match (&self.fingerprint, &self.derivation_path) {
            (Some(fingerprint), Some(derivation_path)) => {
                Ok((*fingerprint, derivation_path.clone()))
            }
            (None, None) => Ok((
                bip32::Fingerprint::from([0u8; 4]),
                bip32::DerivationPath::master(),
            )),
            _ => Err(anyhow!(
                "wallet has only one of fingerprint and derivation path"
            )),
        }
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
