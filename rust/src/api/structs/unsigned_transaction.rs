use flutter_rust_bridge::frb;
use spdk_wallet::{
    bitcoin::{
        consensus::{deserialize, serialize},
        hex::{DisplayHex, FromHex},
        Network,
    },
    client::FeeRate,
    silentpayments::utils::sending::PartialSecret,
};

use crate::api::structs::amount::Amount;
use crate::api::structs::discovered_output::DiscoveredOutput;
use crate::api::structs::input_selection::CoinSelectionStrategy;
use crate::api::structs::recipient::Recipient;

pub struct SilentPaymentUnsignedTransaction {
    pub selected_utxos: Vec<(super::outpoint::OutPoint, DiscoveredOutput)>,
    pub recipients: Vec<Recipient>,
    pub partial_secret: [u8; 32],
    pub unsigned_tx: Option<String>,
    pub network: String,
    /// Wallet change amount (zero for drain / changeless selections).
    pub change: Amount,
    /// Indices into `recipients` that are change outputs.
    pub change_indexes: Vec<u32>,
    pub fee: Amount,
    /// Fee rate in satoshis per virtual byte.
    pub actual_fee_rate: f32,
    pub strategy: CoinSelectionStrategy,
}

impl From<spdk_wallet::client::SilentPaymentUnsignedTransaction>
    for SilentPaymentUnsignedTransaction
{
    fn from(value: spdk_wallet::client::SilentPaymentUnsignedTransaction) -> Self {
        Self {
            selected_utxos: value
                .selected_utxos
                .into_iter()
                .map(|(outpoint, output)| (outpoint.into(), output.into()))
                .collect(),
            recipients: value.recipients.into_iter().map(|r| r.into()).collect(),
            partial_secret: value.partial_secret.secret_bytes(),
            unsigned_tx: value
                .unsigned_tx
                .map(|tx| serialize(&tx).to_lower_hex_string()),
            network: value.network.to_core_arg().to_string(),
            change: value.change.into(),
            change_indexes: value.change_indexes.into_iter().map(|i| i as u32).collect(),
            fee: value.fee.into(),
            actual_fee_rate: value.actual_fee_rate.as_sat_vb(),
            strategy: value.strategy.into(),
        }
    }
}

impl From<SilentPaymentUnsignedTransaction>
    for spdk_wallet::client::SilentPaymentUnsignedTransaction
{
    fn from(value: SilentPaymentUnsignedTransaction) -> Self {
        Self {
            selected_utxos: value
                .selected_utxos
                .into_iter()
                .map(|(outpoint, output)| (outpoint.into(), output.into()))
                .collect(),
            recipients: value
                .recipients
                .into_iter()
                .map(|r| r.try_into().unwrap())
                .collect(),
            partial_secret: PartialSecret::from_slice(&value.partial_secret).unwrap(),
            unsigned_tx: value
                .unsigned_tx
                .map(|tx| deserialize(&Vec::from_hex(&tx).unwrap()).unwrap()),
            network: Network::from_core_arg(&value.network).unwrap(),
            change: value.change.into(),
            change_indexes: value.change_indexes.into_iter().map(|i| i as usize).collect(),
            fee: value.fee.into(),
            actual_fee_rate: FeeRate::from_sat_per_vb(value.actual_fee_rate),
            strategy: value.strategy.into(),
        }
    }
}

impl SilentPaymentUnsignedTransaction {
    #[frb(sync)]
    pub fn get_send_amount(&self) -> Amount {
        let amount = self
            .recipients
            .iter()
            .enumerate()
            .filter(|(i, _)| !self.change_indexes.contains(&(*i as u32)))
            .map(|(_, r)| r.amount.0)
            .sum();

        Amount(amount)
    }

    #[frb(sync)]
    pub fn get_change_amount(&self) -> Amount {
        self.change.clone()
    }

    #[frb(sync)]
    pub fn get_fee_amount(&self) -> Amount {
        self.fee.clone()
    }

    #[frb(sync)]
    pub fn get_recipients(&self) -> Vec<Recipient> {
        self.recipients
            .iter()
            .enumerate()
            .filter(|(i, _)| !self.change_indexes.contains(&(*i as u32)))
            .map(|(_, r)| r.clone())
            .collect()
    }
}
