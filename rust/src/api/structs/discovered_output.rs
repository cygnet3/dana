use spdk_wallet::bitcoin::secp256k1::Scalar;
use spdk_wallet::bitcoin::ScriptBuf;

use crate::api::structs::amount::Amount;

#[derive(Debug, Clone)]
pub struct DiscoveredOutput {
    pub tweak: [u8; 32],
    pub value: Amount,
    pub script_pubkey: String,
    pub label: Option<String>,
}

impl From<spdk_wallet::updater::DiscoveredOutput> for DiscoveredOutput {
    fn from(value: spdk_wallet::updater::DiscoveredOutput) -> Self {
        Self {
            tweak: value.tweak.to_be_bytes(),
            value: value.value.into(),
            script_pubkey: value.script_pubkey.to_hex_string(),
            label: value.label.map(|l| l.as_string()),
        }
    }
}

impl From<DiscoveredOutput> for spdk_wallet::updater::DiscoveredOutput {
    fn from(value: DiscoveredOutput) -> Self {
        Self {
            tweak: Scalar::from_be_bytes(value.tweak).unwrap(),
            value: value.value.into(),
            script_pubkey: ScriptBuf::from_hex(&value.script_pubkey).unwrap(),
            label: value.label.map(|l| l.try_into().unwrap()),
        }
    }
}
