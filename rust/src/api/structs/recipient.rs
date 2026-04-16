use serde::{Deserialize, Serialize};

use crate::api::structs::amount::Amount;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct Recipient {
    pub payment_code: String, // either old school or silent payment
    pub amount: Amount,
}

impl From<spdk_wallet::client::Recipient> for Recipient {
    fn from(value: spdk_wallet::client::Recipient) -> Self {
        Recipient {
            payment_code: value.address.into(),
            amount: value.amount.into(),
        }
    }
}

impl TryFrom<Recipient> for spdk_wallet::client::Recipient {
    type Error = anyhow::Error;
    fn try_from(value: Recipient) -> Result<Self, Self::Error> {
        let recipient_address = value.payment_code.try_into()?;
        let res = Self {
            address: recipient_address,
            amount: value.amount.into(),
        };

        Ok(res)
    }
}
