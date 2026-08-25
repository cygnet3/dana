use crate::api::structs::input_selection::InputSelection;
use crate::api::structs::network::Network;
use crate::api::structs::owned_output::{OwnedOutput, WalletUtxo};
use crate::api::structs::recipient::Recipient;
use crate::wallet::spend_key_derivation_path;

use anyhow::{Error, Result};
use bip39::rand::thread_rng;
use flutter_rust_bridge::frb;
use psbt_v2::v2::{GetKey, GetKeyError, KeyRequest, Output as PsbtOutput};
use spdk_wallet::backend_blindbit_v1::BlindbitClient;
use spdk_wallet::bitcoin::secp256k1::{Secp256k1, SecretKey, Signing};
use spdk_wallet::bitcoin::{
    consensus::serialize, hex::DisplayHex, script::PushBytesBuf, Amount, CompressedPublicKey,
    NetworkKind, PrivateKey, ScriptBuf, TxOut,
};
use spdk_wallet::client::{random_split, RecipientAddress, Strategy};
use spdk_wallet::psbt::roles::{
    Bip375UpdaterExt, ConstructorPsbtExt, ExtractorPsbtExt, InputWitnessFinalizerPsbtExt,
    SignerPsbtExt,
};
use spdk_wallet::psbt::Psbt;
use spdk_wallet::silentpayments::Network as SpNetwork;
use spdk_wallet::DATA_CARRIER_SIZE;

use super::SpWallet;

/// Minimum value of a change output when splitting change into parts
/// (bdk_coin_select::TR_DUST_RELAY_MIN_VALUE * 2).
const MIN_CHANGE_PART_SAT: u64 = 660;

/// The PSBT built for a payment, together with the final recipient list
/// (payment recipient plus any change outputs), used to record the outgoing
/// transaction once it is broadcast.
#[derive(Debug, Clone)]
#[frb]
pub struct CreatedPsbt {
    pub psbt: Vec<u8>,
    pub recipients: Vec<Recipient>,
}

fn to_utxos_and_recipients(
    owned_outputs: Vec<OwnedOutput>,
    api_recipients: Vec<Recipient>,
) -> Result<(Vec<WalletUtxo>, Vec<spdk_wallet::client::Recipient>)> {
    let available_utxos = owned_outputs
        .into_iter()
        .map(|o| o.try_into_utxo())
        .collect::<Result<Vec<_>>>()?;
    let recipients = api_recipients
        .into_iter()
        .map(|r| r.try_into())
        .collect::<Result<Vec<spdk_wallet::client::Recipient>>>()?;
    Ok((available_utxos, recipients))
}

/// Single-key provider for the PSBT signer role: dana is a single-signer
/// wallet, so every input resolves to the same untweaked spend key. The
/// signer applies the per-input `sp_tweak` itself.
struct SingleKeyProvider(SecretKey);

impl GetKey for SingleKeyProvider {
    type Error = GetKeyError;

    fn get_key<C: Signing>(
        &self,
        _key_request: KeyRequest,
        _secp: &Secp256k1<C>,
    ) -> Result<Option<PrivateKey>, Self::Error> {
        Ok(Some(PrivateKey::new(self.0, NetworkKind::Main)))
    }
}

impl SpWallet {
    /// Builds a BIP-375 PSBT (v2) for a previously chosen [InputSelection].
    ///
    /// The returned PSBT has all inputs and outputs set, with silent payment
    /// outputs still carrying placeholder scriptPubKeys (the SP output keys
    /// are only derived at signing time, see [SpWallet::sign_psbt]).
    ///
    /// Also returns the final recipient list (payment recipient plus any
    /// change outputs), so the outgoing transaction can be recorded once the
    /// signed transaction is broadcast.
    #[flutter_rust_bridge::frb(sync)]
    pub fn create_psbt(
        &self,
        owned_outputs: Vec<OwnedOutput>,
        api_recipients: Vec<Recipient>,
        selection: InputSelection,
        network: Network,
    ) -> Result<CreatedPsbt> {
        let (available_utxos, mut recipients) = to_utxos_and_recipients(owned_outputs, api_recipients)?;
        let network = spdk_wallet::bitcoin::Network::from(network);
        let selection = spdk_wallet::client::InputSelection::from(selection);

        let sp_network = match network {
            spdk_wallet::bitcoin::Network::Bitcoin => SpNetwork::Mainnet,
            spdk_wallet::bitcoin::Network::Testnet | spdk_wallet::bitcoin::Network::Signet => {
                SpNetwork::Testnet
            }
            spdk_wallet::bitcoin::Network::Regtest => SpNetwork::Regtest,
            _ => unreachable!(),
        };

        for r in &recipients {
            if let RecipientAddress::SpCode(sp_code) = &r.address {
                if sp_code.network() != sp_network {
                    return Err(Error::msg(format!(
                        "Wrong network for silent payment code {}",
                        sp_code
                    )));
                }
            }
        }

        // append change outputs (drain selections never have change)
        if !matches!(selection.strategy, Strategy::Drain) && selection.change > Amount::ZERO {
            let change_parts = random_split(
                selection.change,
                selection.n_change_outputs,
                Amount::from_sat(MIN_CHANGE_PART_SAT),
                &mut thread_rng(),
            )?;
            for part in change_parts {
                recipients.push(spdk_wallet::client::Recipient {
                    address: RecipientAddress::SpCode(self.client.sp_receiver.change_code()),
                    amount: part,
                });
            }
        }

        let total_outputs_amt: Amount = recipients.iter().map(|r| r.amount).sum();
        if total_outputs_amt != selection.sent + selection.change
            || recipients.len() != selection.n_sent_outputs + selection.n_change_outputs
        {
            return Err(Error::msg(
                "Amount and/or number of outputs mismatch between recipients and selection",
            ));
        }

        let outputs = recipients
            .iter()
            .map(|recipient| match &recipient.address {
                RecipientAddress::LegacyAddress(address) => Ok(PsbtOutput::new(TxOut {
                    value: recipient.amount,
                    script_pubkey: address.clone().require_network(network)?.script_pubkey(),
                })),
                RecipientAddress::SpCode(sp_code) => {
                    // BIP-375: the scriptPubKey stays empty at this stage, it is
                    // derived from the ECDH shares at signing time.
                    let mut sp_info = [0u8; 66];
                    sp_info[..33].copy_from_slice(&sp_code.scan_key().serialize());
                    sp_info[33..].copy_from_slice(&sp_code.m_pubkey().serialize());
                    let mut output = PsbtOutput::new(TxOut {
                        value: recipient.amount,
                        script_pubkey: ScriptBuf::new(),
                    });
                    output.sp_v0_info = Some(sp_info);
                    Ok(output)
                }
                RecipientAddress::Data(data) => {
                    if recipient.amount > Amount::ZERO {
                        return Err(Error::msg("Data output must have an amount of 0!"));
                    }
                    if data.len() > DATA_CARRIER_SIZE {
                        return Err(Error::msg(format!(
                            "Can't embed data of length {}. Max length: {}",
                            data.len(),
                            DATA_CARRIER_SIZE
                        )));
                    }
                    let mut op_return = PushBytesBuf::with_capacity(data.len());
                    op_return.extend_from_slice(data)?;
                    Ok(PsbtOutput::new(TxOut {
                        value: recipient.amount,
                        script_pubkey: ScriptBuf::new_op_return(op_return),
                    }))
                }
            })
            .collect::<Result<Vec<_>>>()?;

        let selected_utxos: Vec<WalletUtxo> = selection
            .selected_utxos
            .iter()
            .map(|op| {
                available_utxos
                    .iter()
                    .find(|(o, _)| o == op)
                    .map(|(o, d)| (*o, d.clone()))
                    .ok_or_else(|| {
                        Error::msg(format!("outpoint {} not found in available_utxos", op))
                    })
            })
            .collect::<Result<_>>()?;

        let mut psbt = Psbt::create_new_transaction(outputs)?
            .add_inputs(selected_utxos.iter().map(|(o, _)| *o).collect())?;

        // updater role: fill in the funding utxos and BIP-375/376 SP fields
        let secp = Secp256k1::new();
        let b_spend = self.client.try_get_secret_spend_key()?;
        let spend_path = spend_key_derivation_path(network);
        for (input, (_, output)) in psbt.inputs.iter_mut().zip(selected_utxos.iter()) {
            input.witness_utxo = Some(TxOut {
                value: output.value,
                script_pubkey: output.script_pubkey.clone(),
            });
            input.set_sp_tweak(output.tweak.to_be_bytes());
            // BIP-376: the map key is the tweaked spend key (what BIP-352 uses
            // for the ECDH), the key source points to the untweaked spend key.
            let tweaked_spend_key = b_spend.add_tweak(&output.tweak)?.public_key(&secp);
            input.set_sp_spend_bip32_derivation(
                CompressedPublicKey(tweaked_spend_key),
                Default::default(),
                spend_path.clone(),
            );
        }

        Ok(CreatedPsbt {
            psbt: psbt.serialize(),
            recipients: recipients.into_iter().map(Into::into).collect(),
        })
    }

    /// Signs a PSBT created by [SpWallet::create_psbt]: generates the ECDH
    /// shares (with DLEQ proofs), derives the SP output scriptPubKeys, signs
    /// every input, finalizes and extracts the transaction.
    #[flutter_rust_bridge::frb(sync)]
    pub fn sign_psbt(&self, psbt: Vec<u8>) -> Result<String> {
        let mut psbt =
            Psbt::deserialize(&psbt).map_err(|e| Error::msg(format!("invalid psbt: {}", e)))?;

        let secp = Secp256k1::new();
        let b_spend = self.client.try_get_secret_spend_key()?;

        psbt.single_signer_generate_ecdh_shares(&secp, b_spend)?;
        let sp_outputs = psbt.compute_sp_outputs(&secp)?;
        psbt.set_sp_scriptpubkey(sp_outputs)?;
        psbt.sign_silent_payment_inputs(&SingleKeyProvider(b_spend), &secp)?;
        psbt.finalize()?;

        let tx = psbt.extract_tx()?;
        Ok(serialize(&tx).to_lower_hex_string())
    }

    // note: should only be used when using regtest, else there is privacy loss!
    pub async fn broadcast_using_blindbit(blindbit_url: String, tx: String) -> Result<String> {
        let blindbit_client = BlindbitClient::new(&blindbit_url)?;

        let res = blindbit_client.forward_tx(tx).await?;

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
                        if !report.success.is_empty() {
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
