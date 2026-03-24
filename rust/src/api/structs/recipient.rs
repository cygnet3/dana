use serde::{Deserialize, Serialize};
use spdk_wallet::client::Recipient;

use crate::api::structs::amount::ApiAmount;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiRecipient {
    pub payment_code: String, // either old school or silent payment
    pub amount: ApiAmount,
}

impl From<Recipient> for ApiRecipient {
    fn from(value: Recipient) -> Self {
        ApiRecipient {
            payment_code: value.address.into(),
            amount: value.amount.into(),
        }
    }
}

impl TryFrom<ApiRecipient> for Recipient {
    type Error = anyhow::Error;
    fn try_from(value: ApiRecipient) -> Result<Self, Self::Error> {
        let recipient_address = value.payment_code.try_into()?;
        let res = Recipient {
            address: recipient_address,
            amount: value.amount.into(),
        };

        Ok(res)
    }
}
