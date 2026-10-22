use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

use crate::api::structs::amount::Amount;

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

impl From<CoinSelectionStrategy> for spdk_wallet::client::Strategy {
    fn from(value: CoinSelectionStrategy) -> Self {
        match value {
            CoinSelectionStrategy::Changeless => Self::Changeless,
            CoinSelectionStrategy::LowestFee => Self::LowestFee,
            CoinSelectionStrategy::FeeRateCap => Self::FeeRateCap,
            CoinSelectionStrategy::Greedy => Self::Greedy,
        }
    }
}

#[derive(Debug)]
pub(crate) enum InputSelectionInner {
    Payment(spdk_wallet::client::CoinSelectProposal),
    Drain(spdk_wallet::client::DrainSelection),
}

/// Opaque coin-selection result. Built only from spdk propose APIs; Dart can
/// inspect display fields via getters but cannot forge the underlying selection.
#[derive(Debug)]
#[frb(opaque)]
pub struct InputSelection {
    inner: InputSelectionInner,
}

impl InputSelection {
    #[frb(sync, getter)]
    pub fn sent(&self) -> Amount {
        match &self.inner {
            InputSelectionInner::Payment(s) => s.sent().into(),
            InputSelectionInner::Drain(s) => s.sent().into(),
        }
    }

    #[frb(sync, getter)]
    pub fn n_sent_outputs(&self) -> usize {
        match &self.inner {
            InputSelectionInner::Payment(s) => s.n_sent_outputs(),
            InputSelectionInner::Drain(s) => s.n_sent_outputs(),
        }
    }

    #[frb(sync, getter)]
    pub fn change(&self) -> Amount {
        match &self.inner {
            InputSelectionInner::Payment(s) => s.change().into(),
            InputSelectionInner::Drain(_) => Amount::zero(),
        }
    }

    #[frb(sync, getter)]
    pub fn fee(&self) -> Amount {
        match &self.inner {
            InputSelectionInner::Payment(s) => s.fee().into(),
            InputSelectionInner::Drain(s) => s.fee().into(),
        }
    }

    /// Fee rate in satoshis per virtual byte.
    #[frb(sync, getter)]
    pub fn actual_fee_rate(&self) -> f32 {
        match &self.inner {
            InputSelectionInner::Payment(s) => s.actual_fee_rate().as_sat_vb(),
            InputSelectionInner::Drain(s) => s.actual_fee_rate().as_sat_vb(),
        }
    }

    /// Strategy used for this selection. `None` for drain selections.
    #[frb(sync, getter)]
    pub fn strategy(&self) -> Option<CoinSelectionStrategy> {
        match &self.inner {
            InputSelectionInner::Payment(s) => Some(s.strategy().into()),
            InputSelectionInner::Drain(_) => None,
        }
    }

    pub(crate) fn as_inner(&self) -> &InputSelectionInner {
        &self.inner
    }
}

impl From<spdk_wallet::client::CoinSelectProposal> for InputSelection {
    fn from(value: spdk_wallet::client::CoinSelectProposal) -> Self {
        Self {
            inner: InputSelectionInner::Payment(value),
        }
    }
}

impl From<spdk_wallet::client::DrainSelection> for InputSelection {
    fn from(value: spdk_wallet::client::DrainSelection) -> Self {
        Self {
            inner: InputSelectionInner::Drain(value),
        }
    }
}
