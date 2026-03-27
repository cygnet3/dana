use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

use crate::api::structs::amount::ApiAmount;
use crate::api::structs::recipient::ApiRecipient;
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub enum ApiRecordedTransaction {
    Incoming(ApiRecordedTransactionIncoming),
    Outgoing(ApiRecordedTransactionOutgoing),
    UnknownOutgoing(ApiRecordedTransactionUnknownOutgoing),
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiRecordedTransactionIncoming {
    pub txid: String,
    pub amount: ApiAmount,
    pub confirmation_height: Option<u32>,
    pub confirmation_blockhash: Option<String>,
}

impl ApiRecordedTransactionIncoming {
    #[frb(sync)]
    pub fn to_string(&self) -> String {
        serde_json::to_string_pretty(&self).unwrap()
    }
}

impl ApiRecordedTransactionOutgoing {
    #[frb(sync)]
    pub fn to_string(&self) -> String {
        serde_json::to_string_pretty(&self).unwrap()
    }

    #[frb(sync)]
    pub fn total_outgoing(&self) -> ApiAmount {
        let sum: u64 = self.recipients.iter().map(|r| r.amount.0).sum();
        // include fee to the total as well
        let fee = self.fee.0;

        ApiAmount(sum + fee)
    }
}

impl ApiRecordedTransactionUnknownOutgoing {
    #[frb(sync)]
    pub fn to_string(&self) -> String {
        serde_json::to_string_pretty(&self).unwrap()
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiRecordedTransactionOutgoing {
    pub txid: String,
    pub spent_outpoints: Vec<super::outpoint::OutPoint>,
    pub recipients: Vec<ApiRecipient>,
    pub confirmation_height: Option<u32>,
    pub confirmation_blockhash: Option<String>,
    pub change: ApiAmount,
    pub fee: ApiAmount,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiRecordedTransactionUnknownOutgoing {
    pub amount: ApiAmount,
    pub confirmation_height: u32,
    pub confirmation_blockhash: Option<String>,
    pub spent_outpoints: Vec<super::outpoint::OutPoint>,
}
