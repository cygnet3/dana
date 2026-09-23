use serde::{Deserialize, Serialize};

use crate::api::structs::amount::Amount;
use crate::api::structs::outpoint::OutPoint;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoinSelectionStrategy {
    Changeless,
    LowestFee,
    FeeRateCap,
    Greedy,
}

impl From<spdk_wallet::client::Strategy> for CoinSelectionStrategy {
    fn from(value: spdk_wallet::client::Strategy) -> Self {
        match value {
            spdk_wallet::client::Strategy::Changeless => Self::Changeless,
            spdk_wallet::client::Strategy::LowestFee => Self::LowestFee,
            spdk_wallet::client::Strategy::FeeRateCap => Self::FeeRateCap,
            spdk_wallet::client::Strategy::Greedy => Self::Greedy,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InputSelection {
    pub selected_utxos: Vec<OutPoint>,
    pub sent: Amount,
    pub n_sent_outputs: usize,
    pub change: Amount,
    pub fee: Amount,
    pub actual_fee_rate: f32,
    pub strategy: Option<CoinSelectionStrategy>,
}

impl From<spdk_wallet::client::CoinSelectProposal> for InputSelection {
    fn from(value: spdk_wallet::client::CoinSelectProposal) -> Self {
        let change = value.change();
        Self {
            selected_utxos: value
                .selected_utxos()
                .iter()
                .copied()
                .map(Into::into)
                .collect(),
            sent: value.sent().into(),
            n_sent_outputs: value.n_sent_outputs(),
            change: change.into(),
            fee: value.fee().into(),
            actual_fee_rate: value.actual_fee_rate().as_sat_vb(),
            strategy: Some(value.strategy().into()),
        }
    }
}

impl From<spdk_wallet::client::DrainSelection> for InputSelection {
    fn from(value: spdk_wallet::client::DrainSelection) -> Self {
        Self {
            selected_utxos: value
                .selected_utxos()
                .iter()
                .copied()
                .map(Into::into)
                .collect(),
            sent: value.sent().into(),
            n_sent_outputs: value.n_sent_outputs(),
            change: Amount::zero(),
            fee: value.fee().into(),
            actual_fee_rate: value.actual_fee_rate().as_sat_vb(),
            strategy: None,
        }
    }
}
