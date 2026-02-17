use serde::{Deserialize, Serialize};
use spdk_core::{
    bitcoin::hex::{self, DisplayHex},
    OutputSpendStatus,
};

type SpendingTxId = String;
type MinedInBlock = String;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub enum ApiOutputSpendStatus {
    Unspent,
    Spent(SpendingTxId),
    Mined(MinedInBlock),
}

impl From<OutputSpendStatus> for ApiOutputSpendStatus {
    fn from(value: OutputSpendStatus) -> Self {
        match value {
            OutputSpendStatus::Unspent => ApiOutputSpendStatus::Unspent,
            OutputSpendStatus::Spent(txid) => {
                ApiOutputSpendStatus::Spent(txid.to_lower_hex_string())
            }
            OutputSpendStatus::Mined(block) => {
                ApiOutputSpendStatus::Mined(block.to_lower_hex_string())
            }
        }
    }
}

impl From<ApiOutputSpendStatus> for OutputSpendStatus {
    fn from(value: ApiOutputSpendStatus) -> Self {
        match value {
            ApiOutputSpendStatus::Unspent => OutputSpendStatus::Unspent,
            ApiOutputSpendStatus::Spent(txid) => {
                OutputSpendStatus::Spent(hex::FromHex::from_hex(&txid).unwrap())
            }
            ApiOutputSpendStatus::Mined(block) => {
                OutputSpendStatus::Mined(hex::FromHex::from_hex(&block).unwrap())
            }
        }
    }
}
