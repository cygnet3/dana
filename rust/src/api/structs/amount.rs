use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Default)]
pub struct ApiAmount(pub u64);

impl From<bitcoin::Amount> for ApiAmount {
    fn from(value: bitcoin::Amount) -> Self {
        ApiAmount(value.to_sat())
    }
}

impl From<ApiAmount> for bitcoin::Amount {
    fn from(value: ApiAmount) -> bitcoin::Amount {
        bitcoin::Amount::from_sat(value.0)
    }
}
