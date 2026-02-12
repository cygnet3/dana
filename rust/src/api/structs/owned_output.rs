use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin::{absolute::Height, ScriptBuf};
use spdk_wallet::client::OwnedOutput;

use crate::api::structs::{amount::ApiAmount, output_spend_info::ApiSpendInfo};

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiOwnedOutput {
    pub blockheight: u32,
    pub tweak: [u8; 32],
    pub amount: ApiAmount,
    pub script: String,
    pub label: Option<String>,
    pub spend_info: ApiSpendInfo,
}

impl From<OwnedOutput> for ApiOwnedOutput {
    fn from(value: OwnedOutput) -> Self {
        ApiOwnedOutput {
            blockheight: value.blockheight.to_consensus_u32(),
            tweak: value.tweak,
            amount: value.amount.into(),
            script: value.script.to_hex_string(),
            label: value.label.map(|l| l.as_string()),
            spend_info: value.spend_info.into(),
        }
    }
}

impl From<ApiOwnedOutput> for OwnedOutput {
    fn from(value: ApiOwnedOutput) -> Self {
        OwnedOutput {
            blockheight: Height::from_consensus(value.blockheight).unwrap(),
            tweak: value.tweak,
            amount: value.amount.into(),
            script: ScriptBuf::from_hex(&value.script).unwrap(),
            label: value.label.map(|l| l.try_into().unwrap()),
            spend_info: value.spend_info.into(),
        }
    }
}
