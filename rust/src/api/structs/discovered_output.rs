use spdk_wallet::{
    bitcoin::{secp256k1::Scalar, ScriptBuf},
    updater::DiscoveredOutput,
};

use crate::api::structs::amount::ApiAmount;

pub struct ApiDiscoveredOutput {
    pub tweak: [u8; 32],
    pub value: ApiAmount,
    pub script_pubkey: String,
    pub label: Option<String>,
}

impl From<DiscoveredOutput> for ApiDiscoveredOutput {
    fn from(value: DiscoveredOutput) -> Self {
        Self {
            tweak: value.tweak.to_be_bytes(),
            value: value.value.into(),
            script_pubkey: value.script_pubkey.to_hex_string(),
            label: value.label.map(|l| l.as_string()),
        }
    }
}

impl From<ApiDiscoveredOutput> for DiscoveredOutput {
    fn from(value: ApiDiscoveredOutput) -> Self {
        Self {
            tweak: Scalar::from_be_bytes(value.tweak).unwrap(),
            value: value.value.into(),
            script_pubkey: ScriptBuf::from_hex(&value.script_pubkey).unwrap(),
            label: value.label.map(|l| l.try_into().unwrap()),
        }
    }
}
