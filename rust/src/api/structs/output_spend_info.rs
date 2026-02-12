use std::str::FromStr;

use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin::{BlockHash, Txid};
use spdk_wallet::client::SpendInfo;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiSpendInfo {
    pub spending_txid: Option<String>,
    pub mined_in_block: Option<String>,
}

impl From<SpendInfo> for ApiSpendInfo {
    fn from(value: SpendInfo) -> Self {
        Self {
            spending_txid: value.spending_txid.map(|txid| txid.to_string()),
            mined_in_block: value.mined_in_block.map(|block| block.to_string()),
        }
    }
}

impl From<ApiSpendInfo> for SpendInfo {
    fn from(value: ApiSpendInfo) -> SpendInfo {
        SpendInfo {
            spending_txid: value.spending_txid.map(|txid| Txid::from_str(&txid).unwrap()),  
            mined_in_block: value.mined_in_block.map(|block| BlockHash::from_str(&block).unwrap()),
        }
    }
}
