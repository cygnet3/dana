use anyhow::Result;
use flutter_rust_bridge::frb;
use spdk_wallet::bitcoin::{OutPoint, TxOut};
use spdk_wallet::silentpayments::SilentPaymentAddress;

use crate::api::structs::amount::ApiAmount;
use crate::api::structs::recipient::ApiRecipient;

#[derive(Debug, Clone)]
pub struct SilentPaymentPsbt(pub Vec<u8>);

impl From<spdk_wallet::SilentPaymentPsbt> for SilentPaymentPsbt {
    fn from(value: spdk_wallet::SilentPaymentPsbt) -> Self {
        Self(value.serialize())
    }
}

impl TryFrom<SilentPaymentPsbt> for spdk_wallet::SilentPaymentPsbt {
    type Error = anyhow::Error;
    fn try_from(value: SilentPaymentPsbt) -> Result<Self, Self::Error> {
        spdk_wallet::SilentPaymentPsbt::deserialize(&value.0).map(|psbt| psbt.into()).map_err(anyhow::Error::msg)
    }
}

impl SilentPaymentPsbt {
    #[frb(sync)]
    pub fn get_selected_outpoints(&self) -> Vec<crate::api::structs::outpoint::OutPoint> {
        let psbt: spdk_wallet::SilentPaymentPsbt = self.clone().try_into().expect("We trust our type");
        psbt.inputs.into_iter().map(|input| {
            OutPoint::new(input.previous_txid, input.spent_output_index).into()
        }).collect()
    }

    #[frb(sync)]
    pub fn get_send_amount(&self, change_payment_code: String) -> ApiAmount {
        let psbt = spdk_wallet::SilentPaymentPsbt::deserialize(&self.0).expect("We trust our type");
        let change_payment_code = SilentPaymentAddress::try_from(change_payment_code).expect("We trust the wallet");
        let mut payment_code_bin: [u8; 66] = [0; 66];
        payment_code_bin[..33].copy_from_slice(&change_payment_code.get_scan_key().serialize());
        payment_code_bin[33..].copy_from_slice(&change_payment_code.get_spend_key().serialize());
        psbt.outputs.iter().filter(|output| 
            output.sp_v0_info.as_ref().map(|vec| vec.as_slice()) != Some(&payment_code_bin)
        ).fold(ApiAmount(0), |acc, output| ApiAmount(acc.0 + output.amount.to_sat()))
    }

    #[frb(sync)]
    pub fn get_change_amount(&self, change_payment_code: String) -> ApiAmount {
        let psbt = spdk_wallet::SilentPaymentPsbt::deserialize(&self.0).expect("We trust our type");
        let change_payment_code = SilentPaymentAddress::try_from(change_payment_code).expect("We trust the wallet");
        let mut payment_code_bin: [u8; 66] = [0; 66];
        payment_code_bin[..33].copy_from_slice(&change_payment_code.get_scan_key().serialize());
        payment_code_bin[33..].copy_from_slice(&change_payment_code.get_spend_key().serialize());
        psbt.outputs.iter().filter(|output| 
            output.sp_v0_info.as_ref().map(|vec| vec.as_slice()) == Some(&payment_code_bin)
        ).fold(ApiAmount(0), |acc, output| ApiAmount(acc.0 + output.amount.to_sat()))
    }

    #[frb(sync)]
    pub fn get_fee_amount(&self) -> Result<ApiAmount> {
        let psbt = spdk_wallet::SilentPaymentPsbt::deserialize(&self.0).expect("We trust our type");
        let funding_utxos = psbt.inputs.iter().map(|input| input.funding_utxo().map_err(anyhow::Error::msg)).collect::<Result<Vec<&TxOut>>>()?;
        let inputs_amount = funding_utxos.iter().fold(ApiAmount(0), |acc, output| {
            ApiAmount(acc.0 + output.value.to_sat())
        });
        let outputs_amount = psbt.outputs.iter().fold(ApiAmount(0), |acc, output| ApiAmount(acc.0 + output.amount.to_sat()));
        Ok(ApiAmount(inputs_amount.0 - outputs_amount.0))
    }

    #[frb(sync)]
    pub fn get_recipients(&self, change_payment_code: String) -> Vec<ApiRecipient> {
        let psbt = spdk_wallet::SilentPaymentPsbt::deserialize(&self.0).expect("We trust our type");
        let change_payment_code = SilentPaymentAddress::try_from(change_payment_code).expect("We trust the wallet");
        let mut payment_code_bin: [u8; 66] = [0; 66];
        payment_code_bin[..33].copy_from_slice(&change_payment_code.get_scan_key().serialize());
        payment_code_bin[33..].copy_from_slice(&change_payment_code.get_spend_key().serialize());
        psbt.outputs.iter().filter(|output| 
            output.sp_v0_info.as_ref().map(|vec| vec.as_slice()) != Some(&payment_code_bin)
        ).map(|output| ApiRecipient {
            payment_code: change_payment_code.into(),
            amount: output.amount.into(),
        }).collect()
    }
}
