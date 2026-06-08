use std::str::FromStr;

use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin::Txid;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, Hash)]
pub struct OutPoint {
    pub txid: String,
    pub vout: u32,
}

impl From<spdk_wallet::bitcoin::OutPoint> for OutPoint {
    fn from(value: spdk_wallet::bitcoin::OutPoint) -> Self {
        Self {
            txid: value.txid.to_string(),
            vout: value.vout,
        }
    }
}

impl From<OutPoint> for spdk_wallet::bitcoin::OutPoint {
    fn from(value: OutPoint) -> Self {
        Self {
            txid: Txid::from_str(&value.txid).unwrap(),
            vout: value.vout,
        }
    }
}
