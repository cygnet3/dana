use flutter_rust_bridge::frb;
use spdk_wallet::{
    bitcoin::{
        consensus::{deserialize, serialize},
        hex::{DisplayHex, FromHex},
        Network,
    },
    silentpayments::utils::sending::PartialSecret,
};

use crate::api::structs::amount::Amount;
use crate::api::structs::discovered_output::DiscoveredOutput;
use crate::api::structs::recipient::{PaymentCode, PaymentCodeKind, Recipient};
use crate::api::structs::silent_payment_code::SilentPaymentCode;

pub struct SilentPaymentUnsignedTransaction {
    pub selected_utxos: Vec<(super::outpoint::OutPoint, DiscoveredOutput)>,
    pub recipients: Vec<Recipient>,
    pub partial_secret: [u8; 32],
    pub unsigned_tx: Option<String>,
    pub network: String,
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
            recipients: value.recipients.into_iter().map(|r| r.into()).collect(),
            partial_secret: PartialSecret::from_slice(&value.partial_secret).unwrap(),
            unsigned_tx: value
                .unsigned_tx
                .map(|tx| deserialize(&Vec::from_hex(&tx).unwrap()).unwrap()),
            network: Network::from_core_arg(&value.network).unwrap(),
        }
    }
}

impl SilentPaymentUnsignedTransaction {
    #[frb(sync)]
    pub fn get_send_amount(&self, change_code: &SilentPaymentCode) -> Amount {
        let amount = self
            .get_recipients(change_code)
            .iter()
            .map(|r| r.amount.0)
            .sum();

        Amount(amount)
    }

    #[frb(sync)]
    pub fn get_change_amount(&self, change_code: &SilentPaymentCode) -> Amount {
        let amount = self
            .recipients
            .iter()
            .filter(|r| is_change(&r.payment_code, change_code))
            .map(|r| r.amount.0)
            .sum();
        Amount(amount)
    }

    #[frb(sync)]
    pub fn get_fee_amount(&self) -> Amount {
        let input_sum: u64 = self.selected_utxos.iter().map(|(_, o)| o.value.0).sum();

        let output_sum: u64 = self.recipients.iter().map(|r| r.amount.0).sum();

        Amount(input_sum - output_sum)
    }

    #[frb(sync)]
    pub fn get_recipients(&self, change_code: &SilentPaymentCode) -> Vec<Recipient> {
        self.recipients
            .iter()
            .filter(|r| is_payment_recipient(&r.payment_code, change_code))
            .cloned()
            .collect()
    }
}

fn is_change(address: &PaymentCode, change_code: &SilentPaymentCode) -> bool {
    address.silent_payment_code().as_ref() == Some(change_code)
}

/// Silent payment outputs other than change, plus bech32/bech32m and Base58Check.
/// OP_RETURN is left out.
fn is_payment_recipient(address: &PaymentCode, change_code: &SilentPaymentCode) -> bool {
    match address.kind() {
        Ok(PaymentCodeKind::SilentPayment) => !is_change(address, change_code),
        Ok(PaymentCodeKind::Bech32 | PaymentCodeKind::Base58) => true,
        Err(_) => false,
    }
}
