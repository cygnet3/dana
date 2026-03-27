use std::str::FromStr;

use flutter_rust_bridge::frb;

use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin::OutPoint;
use spdk_wallet::bitcoin::{absolute::Height, Amount, BlockHash, Txid};
use spdk_wallet::client::Recipient;

use crate::api::structs::recorded_transaction::{
    ApiRecordedTransactionIncoming, ApiRecordedTransactionOutgoing,
    ApiRecordedTransactionUnknownOutgoing,
};

use super::structs::recorded_transaction::ApiRecordedTransaction;
use anyhow::Result;

/// Legacy TxHistory type for migration only.
/// DO NOT USE in new code - use SQLite-backed transaction storage instead.
/// Only kept for reading old wallet data from SharedPreferences during migration.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[frb(opaque)]
pub struct LegacyTxHistoryStruct(Vec<RecordedTransaction>);

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
pub enum RecordedTransaction {
    Incoming(RecordedTransactionIncoming),
    Outgoing(RecordedTransactionOutgoing),
    UnknownOutgoing(RecordedTransactionUnknownOutgoing),
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct RecordedTransactionIncoming {
    txid: Txid,
    amount: Amount,
    confirmation_height: Option<Height>,
    confirmation_blockhash: Option<BlockHash>,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct RecordedTransactionOutgoing {
    txid: Txid,
    spent_outpoints: Vec<OutPoint>,
    recipients: Vec<Recipient>,
    confirmation_height: Option<Height>,
    confirmation_blockhash: Option<BlockHash>,
    change: Amount,
    #[serde(default)]
    fee: Amount,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct RecordedTransactionUnknownOutgoing {
    spent_outpoints: Vec<OutPoint>,
    amount: Amount,
    confirmation_height: Height,
    confirmation_blockhash: BlockHash,
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
            confirmation_height: value.confirmation_height.to_consensus_u32(),
            confirmation_blockhash: value.confirmation_blockhash.to_string(),
            amount: value.amount.into(),
            spent_outpoints: value
                .spent_outpoints
                .into_iter()
                .map(|x| x.into())
                .collect(),
        }
    }
}

impl From<ApiRecordedTransactionUnknownOutgoing> for RecordedTransactionUnknownOutgoing {
    fn from(value: ApiRecordedTransactionUnknownOutgoing) -> Self {
        Self {
            amount: value.amount.into(),
            confirmation_height: Height::from_consensus(value.confirmation_height).unwrap(),
            confirmation_blockhash: BlockHash::from_str(&value.confirmation_blockhash).unwrap(),
            spent_outpoints: value
                .spent_outpoints
                .into_iter()
                .map(|x| x.into())
                .collect(),
        }
    }
}

impl From<RecordedTransactionIncoming> for ApiRecordedTransactionIncoming {
    fn from(value: RecordedTransactionIncoming) -> Self {
        let confirmation_height = value
            .confirmation_height
            .map(|height| height.to_consensus_u32());
        let confirmation_blockhash = value
            .confirmation_blockhash
            .map(|blockhash| blockhash.to_string());

        Self {
            txid: value.txid.to_string(),
            amount: value.amount.into(),
            confirmation_height,
            confirmation_blockhash,
        }
    }
}

impl From<ApiRecordedTransactionIncoming> for RecordedTransactionIncoming {
    fn from(value: ApiRecordedTransactionIncoming) -> Self {
        let confirmation_height = value
            .confirmation_height
            .map(|height| Height::from_consensus(height).unwrap());
        let confirmation_blockhash = value
            .confirmation_blockhash
            .map(|blockhash| BlockHash::from_str(&blockhash).unwrap());

        Self {
            txid: Txid::from_str(&value.txid).unwrap(),
            amount: value.amount.into(),
            confirmation_height,
            confirmation_blockhash,
        }
    }
}

impl From<RecordedTransactionOutgoing> for ApiRecordedTransactionOutgoing {
    fn from(value: RecordedTransactionOutgoing) -> Self {
        let confirmation_height = value
            .confirmation_height
            .map(|height| height.to_consensus_u32());
        let confirmation_blockhash = value
            .confirmation_blockhash
            .map(|blockhash| blockhash.to_string());

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

impl From<ApiRecordedTransactionOutgoing> for RecordedTransactionOutgoing {
    fn from(value: ApiRecordedTransactionOutgoing) -> Self {
        let confirmation_height = value
            .confirmation_height
            .map(|height| Height::from_consensus(height).unwrap());
        let confirmation_blockhash = value
            .confirmation_blockhash
            .map(|blockhash| BlockHash::from_str(&blockhash).unwrap());

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
            confirmation_height,
            confirmation_blockhash,
            change: value.change.into(),
            fee: value.fee.into(),
        }
    }
}
