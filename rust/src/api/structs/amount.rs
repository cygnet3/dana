use flutter_rust_bridge::frb;
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

impl ApiAmount {
    #[frb(sync)]
    pub fn to_int(&self) -> u64 {
        self.0
    }

    #[frb(sync)]
    pub fn display_btc(&self) -> String {
        let amount_btc = self.0 as f32 / 100_000_000 as f32;
        let decimals = format!("{:.8}", amount_btc);
        let len = decimals.len();
        format!(
            "₿ {} {} {}",
            &decimals[..len - 6],
            &decimals[len - 6..len - 3],
            &decimals[len - 3..]
        )
    }

    #[frb(sync)]
    pub fn display_sats(&self) -> String {
        format!("{} sats", self.0)
    }
}
