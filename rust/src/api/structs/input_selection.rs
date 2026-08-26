use serde::{Deserialize, Serialize};
use spdk_wallet::client::FeeRate;

use crate::api::structs::amount::Amount;
use crate::api::structs::outpoint::OutPoint;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoinSelectionStrategy {
    Changeless,
    LowestFee,
    FeeRateCap,
    Greedy,
    Drain,
}

impl From<spdk_wallet::client::Strategy> for CoinSelectionStrategy {
    fn from(value: spdk_wallet::client::Strategy) -> Self {
        match value {
            spdk_wallet::client::Strategy::Changeless => Self::Changeless,
            spdk_wallet::client::Strategy::LowestFee => Self::LowestFee,
            spdk_wallet::client::Strategy::FeeRateCap => Self::FeeRateCap,
            spdk_wallet::client::Strategy::Greedy => Self::Greedy,
            spdk_wallet::client::Strategy::Drain => Self::Drain,
        }
    }
}

impl From<CoinSelectionStrategy> for spdk_wallet::client::Strategy {
    fn from(value: CoinSelectionStrategy) -> Self {
        match value {
            CoinSelectionStrategy::Changeless => Self::Changeless,
            CoinSelectionStrategy::LowestFee => Self::LowestFee,
            CoinSelectionStrategy::FeeRateCap => Self::FeeRateCap,
            CoinSelectionStrategy::Greedy => Self::Greedy,
            CoinSelectionStrategy::Drain => Self::Drain,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InputSelection {
    pub selected_utxos: Vec<OutPoint>,
    pub sent: Amount,
    pub n_sent_outputs: usize,
    pub change: Amount,
    pub n_change_outputs: usize,
    pub fee: Amount,
    /// Fee rate in satoshis per virtual byte.
    pub actual_fee_rate: f32,
    pub strategy: CoinSelectionStrategy,
}

impl From<spdk_wallet::client::InputSelection> for InputSelection {
    fn from(value: spdk_wallet::client::InputSelection) -> Self {
        Self {
            selected_utxos: value.selected_utxos.into_iter().map(Into::into).collect(),
            sent: value.sent.into(),
            n_sent_outputs: value.n_sent_outputs,
            change: value.change.into(),
            n_change_outputs: value.n_change_outputs,
            fee: value.fee.into(),
            actual_fee_rate: value.actual_fee_rate.as_sat_vb(),
            strategy: value.strategy.into(),
        }
    }
}

impl From<InputSelection> for spdk_wallet::client::InputSelection {
    fn from(value: InputSelection) -> Self {
        Self {
            selected_utxos: value.selected_utxos.into_iter().map(Into::into).collect(),
            sent: value.sent.into(),
            n_sent_outputs: value.n_sent_outputs,
            change: value.change.into(),
            n_change_outputs: value.n_change_outputs,
            fee: value.fee.into(),
            actual_fee_rate: FeeRate::from_sat_per_vb(value.actual_fee_rate),
            strategy: value.strategy.into(),
        }
    }
}
