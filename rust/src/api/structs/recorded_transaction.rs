use std::str::FromStr;

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use spdk_core::bitcoin::{absolute::Height, OutPoint, Txid};

use crate::api::structs::amount::ApiAmount;
use crate::api::structs::recipient::ApiRecipient;
use crate::state::constants::{
    RecordedTransaction, RecordedTransactionIncoming, RecordedTransactionOutgoing,
    RecordedTransactionUnknownOutgoing,
};

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
    pub confirmed_at: Option<u32>,
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
    pub spent_outpoints: Vec<String>,
    pub recipients: Vec<ApiRecipient>,
    pub confirmed_at: Option<u32>,
    pub change: ApiAmount,
    pub fee: ApiAmount,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ApiRecordedTransactionUnknownOutgoing {
    pub amount: ApiAmount,
    pub confirmed_at: u32,
    pub spent_outpoints: Vec<String>,
}

impl From<RecordedTransaction> for ApiRecordedTransaction {
    fn from(value: RecordedTransaction) -> Self {
        match value {
            RecordedTransaction::Incoming(incoming) => Self::Incoming(incoming.into()),
            RecordedTransaction::Outgoing(outgoing) => Self::Outgoing(outgoing.into()),
            RecordedTransaction::UnknownOutgoing(unknown) => Self::UnknownOutgoing(unknown.into()),
        }
    }
}

impl From<ApiRecordedTransaction> for RecordedTransaction {
    fn from(value: ApiRecordedTransaction) -> Self {
        match value {
            ApiRecordedTransaction::Incoming(incoming) => Self::Incoming(incoming.into()),
            ApiRecordedTransaction::Outgoing(outgoing) => Self::Outgoing(outgoing.into()),
            ApiRecordedTransaction::UnknownOutgoing(unknown) => {
                Self::UnknownOutgoing(unknown.into())
            }
        }
    }
}

impl From<RecordedTransactionUnknownOutgoing> for ApiRecordedTransactionUnknownOutgoing {
    fn from(value: RecordedTransactionUnknownOutgoing) -> Self {
        Self {
            confirmed_at: value.confirmed_at.to_consensus_u32(),
            amount: value.amount.into(),
            spent_outpoints: value
                .spent_outpoints
                .into_iter()
                .map(|x| x.to_string())
                .collect(),
        }
    }
}

impl From<ApiRecordedTransactionUnknownOutgoing> for RecordedTransactionUnknownOutgoing {
    fn from(value: ApiRecordedTransactionUnknownOutgoing) -> Self {
        Self {
            amount: value.amount.into(),
            confirmed_at: Height::from_consensus(value.confirmed_at).unwrap(),
            spent_outpoints: value
                .spent_outpoints
                .into_iter()
                .map(|x| OutPoint::from_str(&x).unwrap())
                .collect(),
        }
    }
}

impl From<RecordedTransactionIncoming> for ApiRecordedTransactionIncoming {
    fn from(value: RecordedTransactionIncoming) -> Self {
        let confirmed_at = value.confirmed_at.map(|height| height.to_consensus_u32());

        Self {
            txid: value.txid.to_string(),
            amount: value.amount.into(),
            confirmed_at,
        }
    }
}

impl From<ApiRecordedTransactionIncoming> for RecordedTransactionIncoming {
    fn from(value: ApiRecordedTransactionIncoming) -> Self {
        let confirmed_at = value
            .confirmed_at
            .map(|height| Height::from_consensus(height).unwrap());

        Self {
            txid: Txid::from_str(&value.txid).unwrap(),
            amount: value.amount.into(),
            confirmed_at,
        }
    }
}

impl From<RecordedTransactionOutgoing> for ApiRecordedTransactionOutgoing {
    fn from(value: RecordedTransactionOutgoing) -> Self {
        let confirmed_at = value.confirmed_at.map(|height| height.to_consensus_u32());

        Self {
            txid: value.txid.to_string(),
            spent_outpoints: value
                .spent_outpoints
                .into_iter()
                .map(|x| x.to_string())
                .collect(),
            recipients: value.recipients.into_iter().map(Into::into).collect(),
            confirmed_at,
            change: value.change.into(),
            fee: value.fee.into(),
        }
    }
}

impl From<ApiRecordedTransactionOutgoing> for RecordedTransactionOutgoing {
    fn from(value: ApiRecordedTransactionOutgoing) -> Self {
        let confirmed_at = value
            .confirmed_at
            .map(|height| Height::from_consensus(height).unwrap());

        Self {
            txid: Txid::from_str(&value.txid).unwrap(),
            spent_outpoints: value
                .spent_outpoints
                .into_iter()
                .map(|x| OutPoint::from_str(&x).unwrap())
                .collect(),
            recipients: value
                .recipients
                .into_iter()
                .map(|r| r.try_into().unwrap())
                .collect(),
            confirmed_at,
            change: value.change.into(),
            fee: value.fee.into(),
        }
    }
}
