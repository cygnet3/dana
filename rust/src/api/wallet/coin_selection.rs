use crate::api::structs::{
    input_selection::InputSelection,
    owned_output::OwnedOutput,
    recipient::{PaymentCode, Recipient},
};

use anyhow::Result;
use spdk_wallet::client::{
    propose_coin_selections, propose_drain_selection, FeeRate, RecipientAddress,
};

pub fn select_utxos_to_spend(
    owned_outputs: Vec<OwnedOutput>,
    recipient: &Recipient,
    feerate: f32,
) -> Result<Vec<InputSelection>> {
    let available_utxos = OwnedOutput::try_into_utxos(owned_outputs)?;
    let recipients = vec![recipient.clone().into()];

    let selections = propose_coin_selections(
        &available_utxos,
        &recipients,
        FeeRate::from_sat_per_vb(feerate),
    )?;

    Ok(selections.into_iter().map(Into::into).collect())
}

pub fn select_utxos_to_drain(
    owned_outputs: Vec<OwnedOutput>,
    recipient_address: &PaymentCode,
    feerate: f32,
) -> Result<InputSelection> {
    let available_utxos = OwnedOutput::try_into_utxos(owned_outputs)?;
    let recipient_address = RecipientAddress::from(recipient_address.clone());
    let selection = propose_drain_selection(
        &available_utxos,
        &recipient_address,
        FeeRate::from_sat_per_vb(feerate),
    )?;

    Ok(selection.into())
}
