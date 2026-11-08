use crate::api::structs::network::Network;
use crate::api::structs::owned_output::OwnedOutput;
use crate::api::structs::recipient::Recipient;
use crate::api::structs::unsigned_transaction::SilentPaymentUnsignedTransaction;

use anyhow::Result;
use bip39::rand::{thread_rng, RngCore};
use spdk_wallet::backend_blindbit_v1::BlindbitBackend;
use spdk_wallet::bitcoin::secp256k1::Scalar;
use spdk_wallet::bitcoin::ScriptBuf;
use spdk_wallet::bitcoin::{consensus::serialize, hex::DisplayHex, OutPoint, TxOut};
use spdk_wallet::client::{
    propose_coin_selections, propose_drain_selection, FeeRate, RecipientAddress, SpClient,
    Strategy,
};
use spdk_wallet::scanner::DiscoveredOutput;

use super::SpWallet;

impl SpWallet {
    #[flutter_rust_bridge::frb(sync)]
    pub fn create_new_transaction(
        &self,
        owned_outputs: Vec<OwnedOutput>,
        api_recipients: Vec<Recipient>,
        feerate: f32,
        network: Network,
    ) -> Result<SilentPaymentUnsignedTransaction> {
        let client = &self.client;
        let available_utxos: Result<std::collections::HashMap<OutPoint, DiscoveredOutput>> =
            owned_outputs
                .into_iter()
                .map(|output| {
                    let outpoint = output.outpoint.into();
                    let label = match output.label {
                        Some(l) => Some(Scalar::from_be_bytes(l)?.into()),
                        None => None,
                    };
                    let output = DiscoveredOutput {
                        tweak: Scalar::from_be_bytes(output.tweak)?,
                        txout: TxOut {
                            value: output.amount.into(),
                            script_pubkey: ScriptBuf::from_bytes(output.script),
                        },
                        label,
                    };
                    Ok((outpoint, output))
                })
                .collect();
        let available_utxos = available_utxos?;
        let recipients: Vec<spdk_wallet::client::Recipient> = api_recipients
            .into_iter()
            .map(|r| r.try_into().unwrap())
            .collect();

        // spdk now exposes coin selection as explicit proposals; prefer the
        // selection that honours the requested fee rate, then lowest fee
        let proposals =
            propose_coin_selections(&available_utxos, &recipients, FeeRate::from_sat_per_vb(feerate))?;
        let proposal = proposals
            .iter()
            .find(|p| p.strategy() == Strategy::FeeRateCap)
            .or_else(|| proposals.iter().find(|p| p.strategy() == Strategy::LowestFee))
            .ok_or_else(|| anyhow::Error::msg("no viable coin selection"))?;

        let res =
            client.create_transaction_from_proposal(&available_utxos, recipients, proposal, network.into())?;

        Ok(res.into())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn create_drain_transaction(
        &self,
        owned_outputs: Vec<OwnedOutput>,
        wipe_address: String,
        feerate: f32,
        network: Network,
    ) -> Result<SilentPaymentUnsignedTransaction> {
        let client = &self.client;
        let available_utxos: Result<std::collections::HashMap<OutPoint, DiscoveredOutput>> =
            owned_outputs
                .into_iter()
                .map(|output| {
                    let outpoint = output.outpoint.into();
                    let label = match output.label {
                        Some(l) => Some(Scalar::from_be_bytes(l)?.into()),
                        None => None,
                    };
                    let output = DiscoveredOutput {
                        tweak: Scalar::from_be_bytes(output.tweak)?,
                        txout: TxOut {
                            value: output.amount.into(),
                            script_pubkey: ScriptBuf::from_bytes(output.script),
                        },
                        label,
                    };
                    Ok((outpoint, output))
                })
                .collect();
        let available_utxos = available_utxos?;

        let recipient_address: RecipientAddress = RecipientAddress::try_from(wipe_address)?;
        let selection = propose_drain_selection(
            &available_utxos,
            &recipient_address,
            FeeRate::from_sat_per_vb(feerate),
        )?;
        let recipients = vec![spdk_wallet::client::Recipient {
            address: recipient_address,
            amount: selection.sent(),
        }];
        let res = client.create_drain_transaction_from_selection(
            &available_utxos,
            recipients,
            &selection,
            network.into(),
        )?;

        Ok(res.into())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn sign_transaction(
        &self,
        unsigned_transaction: SilentPaymentUnsignedTransaction,
    ) -> Result<String> {
        let mut aux_rand = [0u8; 32];

        let mut rng = thread_rng();
        rng.fill_bytes(&mut aux_rand);

        let client = &self.client;
        let unsigned = unsigned_transaction.into();
        let tx = client.sign_transaction(&unsigned, &aux_rand)?;
        Ok(serialize(&tx).to_lower_hex_string())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn finalize_transaction(
        unsigned_transaction: SilentPaymentUnsignedTransaction,
    ) -> Result<SilentPaymentUnsignedTransaction> {
        let res = SpClient::finalize_transaction(unsigned_transaction.into())?;
        Ok(res.into())
    }

    // note: should only be used when using regtest, else there is privacy loss!
    pub async fn broadcast_using_blindbit(blindbit_url: String, tx: String) -> Result<String> {
        let backend = BlindbitBackend::new(&blindbit_url)?;

        let res = backend.forward_tx(tx).await?;

        Ok(res.to_string())
    }

    pub async fn broadcast_tx(tx: String, network: Network) -> Result<String> {
        let tx: pushtx::Transaction = tx.parse().unwrap();

        let txid = tx.txid();

        let network = match network {
            Network::Mainnet => pushtx::Network::Mainnet,
            Network::Testnet3 => pushtx::Network::Testnet,
            Network::Testnet4 => pushtx::Network::Testnet,
            Network::Signet => pushtx::Network::Signet,
            Network::Regtest => pushtx::Network::Regtest,
        };

        let opts = pushtx::Opts {
            network,
            ..Default::default()
        };

        tokio::task::spawn_blocking(move || {
            let receiver = pushtx::broadcast(vec![tx], opts);

            loop {
                match receiver.recv() {
                    Ok(pushtx::Info::Done(Ok(report))) => {
                        if report.success.len() > 0 {
                            log::info!("broadcasted {} transactions", report.success.len());
                            break;
                        } else {
                            return Err(anyhow::Error::msg("Failed to broadcast transaction, probably unable to connect to Tor peers"));
                        }
                    }
                    Ok(pushtx::Info::Done(Err(err))) => return Err(anyhow::Error::msg(err.to_string())),
                    Ok(_) => {} // Continue for other Info variants
                    Err(recv_err) => {
                        log::error!("Channel recv error: {:?}", recv_err);
                        return Err(anyhow::Error::msg(format!(
                            "Channel closed unexpectedly while waiting for broadcast result: {:?}",
                            recv_err
                        )));
                    }
                }
            }
            Ok(())
        })
        .await??;

        Ok(txid.to_string())
    }
}
