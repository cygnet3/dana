use std::{collections::HashMap, str::FromStr};

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin::{absolute::Height, Amount, OutPoint, Txid};
use spdk_wallet::client::Recipient;

use crate::{
    api::outputs::OwnedOutputs,
    state::constants::{
        RecordedTransaction, RecordedTransactionIncoming, RecordedTransactionOutgoing,
        RecordedTransactionUnknownOutgoing,
    },
    stream::StateUpdate,
};

use super::structs::amount::ApiAmount;
use super::structs::recipient::ApiRecipient;
use super::structs::recorded_transaction::ApiRecordedTransaction;
use anyhow::Result;

#[derive(Debug, Clone, Deserialize, Serialize)]
#[frb(opaque)]
pub struct TxHistory(Vec<RecordedTransaction>);

impl TxHistory {
    #[flutter_rust_bridge::frb(sync)]
    pub fn empty() -> Self {
        Self(vec![])
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn decode(encoded_history: String) -> Result<Self> {
        let decoded: Vec<ApiRecordedTransaction> = serde_json::from_str(&encoded_history)?;

        Ok(Self(decoded.into_iter().map(Into::into).collect()))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn encode(&self) -> Result<String> {
        let encoded = self.to_api_transactions();

        Ok(serde_json::to_string(&encoded)?)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn to_api_transactions(&self) -> Vec<ApiRecordedTransaction> {
        self.0.iter().map(|x| x.clone().into()).collect()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn process_state_update(
        &mut self,
        update: &StateUpdate,
        owned_outputs: &OwnedOutputs,
    ) -> Result<()> {
        match update {
            StateUpdate::Update {
                blkheight,
                blkhash: _,
                found_outputs,
                found_inputs,
            } => {
                let mut unknown_spent_outpoints = vec![];
                for outpoint in found_inputs {
                    // this may confirm the same tx multiple times, but this shouldn't be a problem
                    if !self.confirm_recorded_outgoing_transaction(*outpoint, *blkheight) {
                        // if we're unable to confirm the spent outpoint, it means we don't know
                        // the spending transaction because of a history desync. To keep the
                        // history consistent we make a new 'unknown' spent output for these.
                        unknown_spent_outpoints.push(*outpoint);
                    }
                }

                if !unknown_spent_outpoints.is_empty() {
                    let unknown_sum = unknown_spent_outpoints
                        .iter()
                        .map(|outpoint| owned_outputs.get(outpoint).unwrap().amount)
                        .sum();

                    self.record_unknown_outgoing_transaction(
                        unknown_spent_outpoints,
                        unknown_sum,
                        *blkheight,
                    )?;
                }

                // add new incoming transactions
                let mut txs: HashMap<Txid, Amount> = HashMap::new();
                for (outpoint, output) in found_outputs {
                    // if this transaction is a send-to-self, it may have a change output present.
                    // since we don't deduct change outputs from the sending side,
                    // we shouldn't add the funds on the receiving side either.
                    //
                    // however, in case the user is recovering using a seed phrase,
                    // we should NOT exclude the change output, since we don't have the sending
                    // equivalent.
                    //
                    // since we're a label-less wallet, the only label we use is the change label,
                    // so we simply check if an output is labelled.
                    if output.label.is_some() {
                        if self.check_is_self_send(outpoint.txid) {
                            // if this is both a change output, as well as a tx we sent ourselves,
                            // skip this output
                            continue;
                        }
                    }

                    let entry = txs.entry(outpoint.txid).or_default();
                    *entry += output.amount;
                }
                for (txid, amount) in txs {
                    self.record_incoming_transaction(txid, amount, *blkheight);
                }
            }
            StateUpdate::NoUpdate { .. } => (),
        }

        Ok(())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn add_outgoing_tx_to_history(
        &mut self,
        txid: String,
        spent_outpoints: Vec<String>,
        recipients: Vec<ApiRecipient>,
        change: ApiAmount,
        fee: ApiAmount,
    ) -> Result<()> {
        let txid = Txid::from_str(&txid)?;
        let spent_outpoints = spent_outpoints
            .into_iter()
            .map(|x| OutPoint::from_str(&x).unwrap())
            .collect();

        let recipients = recipients
            .into_iter()
            .map(|r| r.try_into().unwrap())
            .collect();

        self.record_outgoing_transaction(
            txid,
            spent_outpoints,
            recipients,
            change.into(),
            fee.into(),
        );

        Ok(())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn reset_to_height(&mut self, height: u32) -> Result<()> {
        let blkheight = Height::from_consensus(height)?;
        self.0.retain(|tx| match tx {
            RecordedTransaction::Incoming(incoming) => {
                incoming.confirmed_at.is_some_and(|x| x <= blkheight)
            }
            RecordedTransaction::Outgoing(outgoing) => {
                outgoing.confirmed_at.is_some_and(|x| x <= blkheight)
            }
            RecordedTransaction::UnknownOutgoing(unknown) => unknown.confirmed_at <= blkheight,
        });

        Ok(())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_unconfirmed_change(&self) -> ApiAmount {
        self.0
            .iter()
            .filter_map(|x| match x {
                RecordedTransaction::Outgoing(outgoing) if outgoing.confirmed_at.is_none() => {
                    Some(outgoing.change)
                }
                _ => None,
            })
            .sum::<Amount>()
            .into()
    }

    fn record_outgoing_transaction(
        &mut self,
        txid: Txid,
        spent_outpoints: Vec<OutPoint>,
        recipients: Vec<Recipient>,
        change: Amount,
        fee: Amount,
    ) {
        self.0
            .push(RecordedTransaction::Outgoing(RecordedTransactionOutgoing {
                txid,
                spent_outpoints,
                recipients,
                confirmed_at: None,
                change,
                fee,
            }))
    }

    fn confirm_recorded_outgoing_transaction(
        &mut self,
        outpoint: OutPoint,
        blkheight: Height,
    ) -> bool {
        for recorded_tx in self.0.iter_mut() {
            match recorded_tx {
                RecordedTransaction::Outgoing(outgoing)
                    if (outgoing.spent_outpoints.contains(&outpoint)) =>
                {
                    outgoing.confirmed_at = Some(blkheight);
                    return true;
                }
                _ => (),
            }
        }

        log::warn!("No outgoing tx found for input: {}", outpoint);
        false
    }

    pub(crate) fn record_unknown_outgoing_transaction(
        &mut self,
        spent_outpoints: Vec<OutPoint>,
        amount: Amount,
        confirmed_at: Height,
    ) -> Result<()> {
        self.0.push(RecordedTransaction::UnknownOutgoing(
            RecordedTransactionUnknownOutgoing {
                spent_outpoints,
                amount,
                confirmed_at,
            },
        ));
        Ok(())
    }

    fn record_incoming_transaction(&mut self, txid: Txid, amount: Amount, confirmed_at: Height) {
        self.0
            .push(RecordedTransaction::Incoming(RecordedTransactionIncoming {
                txid,
                amount,
                confirmed_at: Some(confirmed_at),
            }))
    }

    // check if this is a transaction we have sent ourselves
    fn check_is_self_send(&self, txid: Txid) -> bool {
        for history in self.0.iter() {
            if let RecordedTransaction::Outgoing(outgoing) = history {
                if outgoing.txid == txid {
                    return true;
                }
            }
        }
        false
    }
}
