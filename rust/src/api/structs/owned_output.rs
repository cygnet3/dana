use serde::{Deserialize, Serialize};
use spdk_core::{
    bitcoin::{absolute::Height, ScriptBuf},
    OwnedOutput,
};

use crate::api::structs::amount::ApiAmount;
use crate::api::structs::output_spend_status::ApiOutputSpendStatus;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiOwnedOutput {
    pub blockheight: u32,
    pub tweak: [u8; 32],
    pub amount: ApiAmount,
    pub script: String,
    pub label: Option<String>,
    pub spend_status: ApiOutputSpendStatus,
}

impl From<OwnedOutput> for ApiOwnedOutput {
    fn from(value: OwnedOutput) -> Self {
        ApiOwnedOutput {
            blockheight: value.blockheight.to_consensus_u32(),
            tweak: value.tweak,
            amount: value.amount.into(),
            script: value.script.to_hex_string(),
            label: value.label.map(|l| l.as_string()),
            spend_status: value.spend_status.into(),
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
            spend_status: value.spend_status.into(),
        }
    }
}
