use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Default)]
pub struct Amount(pub u64);

impl Amount {
    #[frb(sync)]
    pub fn zero() -> Self {
        Self(0)
    }
}

impl From<bitcoin::Amount> for Amount {
    fn from(value: bitcoin::Amount) -> Self {
        Amount(value.to_sat())
    }
}

impl From<Amount> for bitcoin::Amount {
    fn from(value: Amount) -> bitcoin::Amount {
        bitcoin::Amount::from_sat(value.0)
    }
}
