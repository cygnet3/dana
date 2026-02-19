mod info;
mod scan;
pub mod setup;
mod transaction;

use crate::{api::structs::network::ApiNetwork, wallet::WalletFingerprint};
use anyhow::Result;
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin::secp256k1::SecretKey;
use spdk_wallet::client::{SpClient, SpendKey};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[frb(opaque)]
pub struct SpWallet {
    client: SpClient,
    wallet_fingerprint: WalletFingerprint,
}

impl SpWallet {
    #[frb(sync)]
    pub fn new(scan_key: ApiScanKey, spend_key: ApiSpendKey, network: ApiNetwork) -> Result<Self> {
        let client = SpClient::new(scan_key.into(), spend_key.into(), network.into())?;

        let wallet_fingerprint = client.get_client_fingerprint()?;

        Ok(Self {
            client,
            wallet_fingerprint,
        })
    }

    #[frb(sync)]
    pub fn decode(encoded_wallet: String) -> Result<Self> {
        Ok(serde_json::from_str(&encoded_wallet)?)
    }

    #[frb(sync)]
    pub fn encode(&self) -> Result<String> {
        Ok(serde_json::to_string(&self)?)
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
