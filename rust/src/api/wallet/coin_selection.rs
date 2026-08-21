use crate::api::structs::{
    input_selection::InputSelection, owned_output::OwnedOutput, recipient::Recipient,
};

use anyhow::Result;
use spdk_wallet::client::{
    propose_coin_selections, propose_drain_selection, FeeRate, RecipientAddress, Strategy,
};

/// Pick the preferred selection out of the candidates produced by the
/// coin-selection strategies: a changeless transaction first (no change
/// output to fingerprint), then the lowest fee, then the greedy fallback.
pub(crate) fn pick_default_selection(
    mut selections: Vec<spdk_wallet::client::InputSelection>,
) -> Result<spdk_wallet::client::InputSelection> {
    for preferred in [Strategy::Changeless, Strategy::LowestFee, Strategy::Greedy] {
        if let Some(pos) = selections.iter().position(|s| s.strategy == preferred) {
            return Ok(selections.swap_remove(pos));
        }
    }
    selections
        .into_iter()
        .next()
        .ok_or_else(|| anyhow::Error::msg("no successful coin selection"))
}

pub fn select_utxos_to_spend(
    owned_outputs: Vec<OwnedOutput>,
    recipients: Vec<Recipient>,
    n_change_outputs: usize,
    feerate: f32,
) -> Result<Vec<InputSelection>> {
    let available_utxos = owned_outputs
        .into_iter()
        .map(|o| o.try_into_utxo())
        .collect::<Result<Vec<_>>>()?;
    let recipients = recipients
        .into_iter()
        .map(|r| r.try_into())
        .collect::<Result<Vec<spdk_wallet::client::Recipient>>>()?;

    let selections = propose_coin_selections(
        &available_utxos,
        &recipients,
        FeeRate::from_sat_per_vb(feerate),
        n_change_outputs,
    )?;

    Ok(selections.into_iter().map(Into::into).collect())
}

pub fn select_utxos_to_drain(
    owned_outputs: Vec<OwnedOutput>,
    recipient_address: String,
    feerate: f32,
) -> Result<InputSelection> {
    let available_utxos = owned_outputs
        .into_iter()
        .map(|o| o.try_into_utxo())
        .collect::<Result<Vec<_>>>()?;
    let recipient_address = RecipientAddress::try_from(recipient_address)?;

    let selection = propose_drain_selection(
        &available_utxos,
        &recipient_address,
        FeeRate::from_sat_per_vb(feerate),
    )?;

    Ok(selection.into())
}
