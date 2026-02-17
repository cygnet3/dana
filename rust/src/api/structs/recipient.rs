use crate::api::structs::amount::ApiAmount;
use serde::{Deserialize, Serialize};
use spdk_core::Recipient;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiRecipient {
    pub address: String, // either old school or silent payment
    pub amount: ApiAmount,
}

impl From<Recipient> for ApiRecipient {
    fn from(value: Recipient) -> Self {
        ApiRecipient {
            address: value.address.into(),
            amount: value.amount.into(),
        }
    }
}

impl TryFrom<ApiRecipient> for Recipient {
    type Error = anyhow::Error;
    fn try_from(value: ApiRecipient) -> Result<Self, Self::Error> {
        let address = value.address.try_into()?;
        let res = Recipient {
            address,
            amount: value.amount.into(),
        };

        Ok(res)
    }
}
