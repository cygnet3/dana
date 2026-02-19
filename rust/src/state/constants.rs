use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin::{absolute::Height, Amount, OutPoint, Txid};
use spdk_wallet::client::Recipient;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub enum RecordedTransaction {
    Incoming(RecordedTransactionIncoming),
    Outgoing(RecordedTransactionOutgoing),
    UnknownOutgoing(RecordedTransactionUnknownOutgoing),
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct RecordedTransactionIncoming {
    pub txid: Txid,
    pub amount: Amount,
    pub confirmed_at: Option<Height>,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct RecordedTransactionOutgoing {
    pub txid: Txid,
    pub spent_outpoints: Vec<OutPoint>,
    pub recipients: Vec<Recipient>,
    pub confirmed_at: Option<Height>,
    pub change: Amount,
    #[serde(default)]
    pub fee: Amount,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct RecordedTransactionUnknownOutgoing {
    pub spent_outpoints: Vec<OutPoint>,
    pub amount: Amount,
    pub confirmed_at: Height,
}
