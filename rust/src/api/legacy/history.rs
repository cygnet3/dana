use std::str::FromStr;

use flutter_rust_bridge::frb;

use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin::OutPoint;
use spdk_wallet::bitcoin::{absolute::Height, Amount, Txid};
use spdk_wallet::client::Recipient;

use crate::api::structs::recorded_transaction::{
    ApiRecordedTransaction, ApiRecordedTransactionIncoming, ApiRecordedTransactionOutgoing,
    ApiRecordedTransactionUnknownOutgoing,
};

use anyhow::Result;

/// Legacy TxHistory type for migration only.
/// DO NOT USE in new code - use SQLite-backed transaction storage instead.
/// Only kept for reading old wallet data from SharedPreferences during migration.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[frb(opaque)]
pub struct LegacyTxHistoryStruct(Vec<LegacyRecordedTransactionStruct>);

impl LegacyTxHistoryStruct {
    /// Create an empty transaction history.
    /// Only used for migration/backup compatibility.
    #[flutter_rust_bridge::frb(sync)]
    pub fn empty() -> Self {
        Self(vec![])
    }

    /// Decode transaction history from JSON string.
    /// Only used during migration from SharedPreferences to SQLite.
    #[flutter_rust_bridge::frb(sync)]
    pub fn decode(encoded_history: String) -> Result<Self> {
        let deserialized = serde_json::from_str(&encoded_history)?;

        Ok(deserialized)
    }

    /// Convert to API transaction list for migration.
    /// Only used during migration from SharedPreferences to SQLite.
    #[flutter_rust_bridge::frb(sync)]
    pub fn to_api_transactions(&self) -> Vec<ApiRecordedTransaction> {
        self.0.iter().map(|x| x.clone().into()).collect()
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub enum LegacyRecordedTransactionStruct {
    Incoming(LegacyRecordedTransactionIncomingStruct),
    Outgoing(LegacyRecordedTransactionOutgoingStruct),
    UnknownOutgoing(LegacyRecordedTransactionUnknownOutgoingStruct),
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct LegacyRecordedTransactionIncomingStruct {
    txid: Txid,
    amount: Amount,
    confirmed_at: Option<Height>,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct LegacyRecordedTransactionOutgoingStruct {
    txid: Txid,
    spent_outpoints: Vec<OutPoint>,
    recipients: Vec<Recipient>,
    confirmed_at: Option<Height>,
    change: Amount,
    #[serde(default)]
    fee: Amount,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct LegacyRecordedTransactionUnknownOutgoingStruct {
    spent_outpoints: Vec<OutPoint>,
    amount: Amount,
    confirmed_at: Height,
}

impl From<LegacyRecordedTransactionStruct> for ApiRecordedTransaction {
    fn from(value: LegacyRecordedTransactionStruct) -> Self {
        match value {
            LegacyRecordedTransactionStruct::Incoming(incoming) => Self::Incoming(incoming.into()),
            LegacyRecordedTransactionStruct::Outgoing(outgoing) => Self::Outgoing(outgoing.into()),
            LegacyRecordedTransactionStruct::UnknownOutgoing(unknown) => {
                Self::UnknownOutgoing(unknown.into())
            }
        }
    }
}

impl From<ApiRecordedTransaction> for LegacyRecordedTransactionStruct {
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

impl From<LegacyRecordedTransactionUnknownOutgoingStruct>
    for ApiRecordedTransactionUnknownOutgoing
{
    fn from(value: LegacyRecordedTransactionUnknownOutgoingStruct) -> Self {
        Self {
            confirmation_height: value.confirmed_at.to_consensus_u32(),
            confirmation_blockhash: None,
            amount: value.amount.into(),
            spent_outpoints: value
                .spent_outpoints
                .into_iter()
                .map(|x| x.into())
                .collect(),
        }
    }
}

impl From<ApiRecordedTransactionUnknownOutgoing>
    for LegacyRecordedTransactionUnknownOutgoingStruct
{
    fn from(value: ApiRecordedTransactionUnknownOutgoing) -> Self {
        Self {
            amount: value.amount.into(),
            confirmed_at: Height::from_consensus(value.confirmation_height).unwrap(),
            spent_outpoints: value
                .spent_outpoints
                .into_iter()
                .map(|x| x.into())
                .collect(),
        }
    }
}

impl From<LegacyRecordedTransactionIncomingStruct> for ApiRecordedTransactionIncoming {
    fn from(value: LegacyRecordedTransactionIncomingStruct) -> Self {
        let confirmation_height = value.confirmed_at.map(|height| height.to_consensus_u32());
        let confirmation_blockhash = None;

        Self {
            txid: value.txid.to_string(),
            amount: value.amount.into(),
            confirmation_height,
            confirmation_blockhash,
        }
    }
}

impl From<ApiRecordedTransactionIncoming> for LegacyRecordedTransactionIncomingStruct {
    fn from(value: ApiRecordedTransactionIncoming) -> Self {
        let confirmation_height = value
            .confirmation_height
            .map(|height| Height::from_consensus(height).unwrap());

        Self {
            txid: Txid::from_str(&value.txid).unwrap(),
            amount: value.amount.into(),
            confirmed_at: confirmation_height,
        }
    }
}

impl From<LegacyRecordedTransactionOutgoingStruct> for ApiRecordedTransactionOutgoing {
    fn from(value: LegacyRecordedTransactionOutgoingStruct) -> Self {
        let confirmation_height = value.confirmed_at.map(|height| height.to_consensus_u32());
        let confirmation_blockhash = None;

        Self {
            txid: value.txid.to_string(),
            spent_outpoints: value
                .spent_outpoints
                .into_iter()
                .map(|x| x.into())
                .collect(),
            recipients: value.recipients.into_iter().map(Into::into).collect(),
            confirmation_height,
            confirmation_blockhash,
            change: value.change.into(),
            fee: value.fee.into(),
        }
    }
}

impl From<ApiRecordedTransactionOutgoing> for LegacyRecordedTransactionOutgoingStruct {
    fn from(value: ApiRecordedTransactionOutgoing) -> Self {
        let confirmed_at = value
            .confirmation_height
            .map(|height| Height::from_consensus(height).unwrap());

        Self {
            txid: Txid::from_str(&value.txid).unwrap(),
            spent_outpoints: value
                .spent_outpoints
                .into_iter()
                .map(|x| x.into())
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
