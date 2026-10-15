pub mod coin_selection;
mod info;
pub mod setup;
mod sync;
mod transaction;

use std::fmt;

use crate::{api::structs::network::Network, wallet::WalletFingerprint};
use anyhow::Result;
use flutter_rust_bridge::frb;
use serde::de::{EnumAccess, VariantAccess, Visitor};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use spdk_wallet::bitcoin::secp256k1::{PublicKey, SecretKey};
use spdk_wallet::client::{SpClient, SpendKey};

#[derive(Debug, Clone)]
#[frb(opaque)]
pub struct SpWallet {
    client: SpClient,
    #[allow(unused)]
    wallet_fingerprint: WalletFingerprint,
}

impl SpWallet {
    #[frb(sync)]
    pub fn new(scan_key: ApiScanKey, spend_key: ApiSpendKey, network: Network) -> Result<Self> {
        let client = SpClient::new(scan_key.into(), spend_key.into(), network.into())?;

        let wallet_fingerprint = client.client_fingerprint()?;

        Ok(Self {
            client,
            wallet_fingerprint,
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

#[derive(Debug, Clone, PartialEq)]
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

// Wire format is the old derived `SpendKey` encoding already stored on device:
// {"Secret":"<64 hex>"} or {"Public":"<compressed hex>"}.
impl Serialize for ApiSpendKey {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match &self.0 {
            SpendKey::Secret(secret) => {
                // Own a copy so Drop can erase it without touching the key `SpendKey` still holds.
                let hex = SecretKeyHex(*secret);
                serializer.serialize_newtype_variant("SpendKey", 0, "Secret", &hex)
            }
            SpendKey::Public(public) => {
                serializer.serialize_newtype_variant("SpendKey", 1, "Public", public)
            }
        }
    }
}

impl<'de> Deserialize<'de> for ApiSpendKey {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        const VARIANTS: &[&str] = &["Secret", "Public"];
        deserializer.deserialize_enum("SpendKey", VARIANTS, SpendKeyVisitor)
    }
}

/// Copy of a spend secret used only to write its hex form.
struct SecretKeyHex(SecretKey);

impl Serialize for SecretKeyHex {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut displayed = self.0.display_secret();
        let encoded = serializer.collect_str(&displayed);
        // `DisplaySecret` has no `Drop`. Erase that copy once the hex is written.
        displayed.non_secure_erase();
        encoded
    }
}

impl Drop for SecretKeyHex {
    fn drop(&mut self) {
        self.0.non_secure_erase();
    }
}

struct SpendKeyVisitor;

impl<'de> Visitor<'de> for SpendKeyVisitor {
    type Value = ApiSpendKey;

    fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
        formatter.write_str("a spend key")
    }

    fn visit_enum<A: EnumAccess<'de>>(self, data: A) -> Result<Self::Value, A::Error> {
        let (tag, variant) = data.variant::<SpendKeyTag>()?;
        match tag {
            SpendKeyTag::Secret => Ok(ApiSpendKey(SpendKey::Secret(
                variant.newtype_variant::<SecretKey>()?,
            ))),
            SpendKeyTag::Public => Ok(ApiSpendKey(SpendKey::Public(
                variant.newtype_variant::<PublicKey>()?,
            ))),
        }
    }
}

#[derive(Deserialize)]
#[serde(variant_identifier)]
enum SpendKeyTag {
    Secret,
    Public,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn secret() -> SecretKey {
        SecretKey::from_slice(&[0x11; 32]).unwrap()
    }

    #[test]
    fn secret_spend_key_round_trips_without_debug_leak() {
        let key = ApiSpendKey(SpendKey::Secret(secret()));
        let encoded = key.encode().unwrap();
        let hex = "11".repeat(32);

        assert_eq!(encoded, format!(r#"{{"Secret":"{hex}"}}"#));
        assert_eq!(ApiSpendKey::decode(encoded).unwrap(), key);
        assert!(!format!("{key:?}").contains(&hex));
    }

    #[test]
    fn public_spend_key_round_trips() {
        let public = secret().public_key(&spdk_wallet::bitcoin::key::Secp256k1::signing_only());
        let key = ApiSpendKey(SpendKey::Public(public));
        let encoded = key.encode().unwrap();

        assert_eq!(encoded, format!(r#"{{"Public":"{public}"}}"#));
        assert_eq!(ApiSpendKey::decode(encoded).unwrap(), key);
    }
}
