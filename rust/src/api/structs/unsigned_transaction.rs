use flutter_rust_bridge::frb;
use spdk_wallet::bitcoin::{
    consensus::{deserialize, serialize},
    hex::{DisplayHex, FromHex},
    secp256k1::SecretKey,
    Network,
};

use crate::api::structs::amount::Amount;
use crate::api::structs::discovered_output::DiscoveredOutput;
use crate::api::structs::recipient::Recipient;

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
            recipients: value
                .recipients
                .into_iter()
                .map(|r| r.try_into().unwrap())
                .collect(),
            partial_secret: SecretKey::from_slice(&value.partial_secret).unwrap(),
            unsigned_tx: value
                .unsigned_tx
                .map(|tx| deserialize(&Vec::from_hex(&tx).unwrap()).unwrap()),
            network: Network::from_core_arg(&value.network).unwrap(),
        }
    }
}

impl SilentPaymentUnsignedTransaction {
    #[frb(sync)]
    pub fn get_send_amount(&self, change_address: String) -> Amount {
        let amount = self
            .recipients
            .iter()
            .filter_map(|r| {
                if r.payment_code != change_address {
                    Some(r.amount.0)
                } else {
                    None
                }
            })
            .sum();

        Amount(amount)
    }

    #[frb(sync)]
    pub fn get_change_amount(&self, change_address: String) -> Amount {
        let amount = self
            .recipients
            .iter()
            .filter_map(|r| {
                if r.payment_code == change_address {
                    Some(r.amount.0)
                } else {
                    None
                }
            })
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
    pub fn get_recipients(&self, change_address: String) -> Vec<Recipient> {
        self.recipients
            .iter()
            .filter(|r| r.payment_code != change_address)
            .cloned()
            .collect()
    }
}
