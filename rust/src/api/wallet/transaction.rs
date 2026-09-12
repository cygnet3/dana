use crate::api::structs::amount::Amount as ApiAmount;
use crate::api::structs::input_selection::InputSelection;
use crate::api::structs::network::Network;
use crate::api::structs::outpoint::OutPoint as ApiOutPoint;
use crate::api::structs::owned_output::{OwnedOutput, WalletUtxo};
use crate::api::structs::recipient::Recipient;

use anyhow::{Error, Result};
use bip39::rand::seq::SliceRandom;
use bip39::rand::thread_rng;
use flutter_rust_bridge::frb;
use psbt_v2::psbt::{Creator, Finalizer, GetKey, GetKeyError, KeyRequest, Psbt};
use psbt_v2::{Extractor, Input, Output as PsbtOutput, SpV0Info};
use spdk_wallet::backend_blindbit_v1::BlindbitClient;
use spdk_wallet::bitcoin::bip32;
use spdk_wallet::bitcoin::consensus::encode::{deserialize_hex, serialize};
use spdk_wallet::bitcoin::hex::DisplayHex;
use spdk_wallet::bitcoin::secp256k1::{Secp256k1, SecretKey, Signing};
use spdk_wallet::bitcoin::{
    script::PushBytesBuf, Amount, CompressedPublicKey, NetworkKind, PrivateKey, ScriptBuf,
    Transaction, TxOut, XOnlyPublicKey,
};
use spdk_wallet::client::{random_split, RecipientAddress, Strategy};
use spdk_wallet::psbt::roles::{Bip375UpdaterExt, ShareMode, SpSignerExt};
use spdk_wallet::silentpayments::utils::receiving::{get_pubkey_from_input, PublicTweakData};
use spdk_wallet::silentpayments::utils::OutPoint as SpOutPoint;
use spdk_wallet::silentpayments::{
    Network as SpNetwork, TransactionInputs, TransactionSharedSecret,
};
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

/// Spend-key provider for the PSBT signer role. Returns the untweaked spend
/// key only when the BIP-32 key request matches this wallet's origin. The
/// signer applies the per-input `sp_tweak` itself.
struct SpendKeyProvider {
    spend: SecretKey,
    fingerprint: bip32::Fingerprint,
    derivation_path: bip32::DerivationPath,
    network: NetworkKind,
}

impl GetKey for SpendKeyProvider {
    type Error = GetKeyError;

    fn get_key<C: Signing>(
        &self,
        key_request: KeyRequest,
        _secp: &Secp256k1<C>,
    ) -> Result<Option<PrivateKey>, Self::Error> {
        match key_request {
            KeyRequest::Bip32((fingerprint, path))
                if fingerprint == self.fingerprint && path == self.derivation_path =>
            {
                Ok(Some(PrivateKey::new(self.spend, self.network)))
            }
            // Pubkey requests carry the tweaked spend key (the PSBT map key).
            // Serving them would skip the origin check; the signer still
            // applies `sp_tweak` to whatever we return.
            _ => Ok(None),
        }
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
        let (available_utxos, mut recipients) =
            to_utxos_and_recipients(owned_outputs, api_recipients)?;
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
        let expected_outputs_amt = selection.sent + selection.change;
        if total_outputs_amt != expected_outputs_amt {
            return Err(Error::msg(format!(
                "Amount mismatch between recipients and selection: recipients total {}, expected sent+change {}",
                total_outputs_amt, expected_outputs_amt,
            )));
        }
        let expected_n_outputs = selection.n_sent_outputs + selection.n_change_outputs;
        if recipients.len() != expected_n_outputs {
            return Err(Error::msg(format!(
                "Number of outputs mismatch between recipients and selection: recipients {}, expected n_sent+n_change {}",
                recipients.len(), expected_n_outputs,
            )));
        }

        let mut outputs = recipients
            .iter()
            .map(|recipient| match &recipient.address {
                RecipientAddress::LegacyAddress(address) => Ok(PsbtOutput::new(TxOut {
                    value: recipient.amount,
                    script_pubkey: address.clone().require_network(network)?.script_pubkey(),
                })),
                RecipientAddress::SpCode(sp_code) => {
                    // BIP-375: the scriptPubKey stays empty at this stage, it is
                    // derived from the ECDH shares at signing time.
                    let sp_info = SpV0Info::new(CompressedPublicKey(sp_code.scan_key()), CompressedPublicKey(sp_code.m_pubkey()));
                    let output = PsbtOutput {
                        sp_v0_info: Some(sp_info),
                        amount: recipient.amount,
                        ..Default::default()
                    };
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

        outputs.shuffle(&mut thread_rng());

        let secp = Secp256k1::new();
        let b_spend = self.client.try_secret_spend_key()?;
        let (fingerprint, derivation_path) = self.psbt_key_source()?;
        let (spend_xonly, _) = b_spend.x_only_public_key(&secp);

        let mut constructor = Creator::new().constructor_modifiable();
        for output in outputs {
            constructor = constructor
                .output(output)
                .map_err(|e| Error::msg(e.to_string()))?;
        }
        for (outpoint, output) in &selected_utxos {
            let mut input = Input::new(outpoint);
            input.witness_utxo = Some(TxOut {
                value: output.value,
                script_pubkey: output.script_pubkey.clone(),
            });
            input.set_sp_tweak(output.tweak.to_be_bytes());
            // BIP-376: the map key is the untweaked spend key B_spend; the signer
            // applies sp_tweak and negates d if odd (see psbt_v2 sign_with_tweaked_key).
            input.set_sp_spend_bip32_derivation(
                CompressedPublicKey(b_spend.public_key(&secp)),
                fingerprint,
                derivation_path.clone(),
            );
            // BIP-375 signer checks look at tap_key_origins (not the BIP-376 map)
            // for P2TR inputs that carry a DLEQ proof. SP inputs have no internal
            // key, so declare the untweaked spend key's origin here.
            input
                .tap_key_origins
                .insert(spend_xonly, (Vec::new(), (fingerprint, derivation_path.clone())));
            constructor = constructor.input(input);
        }
        let psbt = constructor
            .psbt()
            .map_err(|e| Error::msg(e.to_string()))?;

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
        let b_spend = self.client.try_secret_spend_key()?;
        let (fingerprint, derivation_path) = self.psbt_key_source()?;

        let keys = SpendKeyProvider {
            spend: b_spend,
            fingerprint,
            derivation_path,
            network: NetworkKind::from(self.client.network()),
        };
        psbt.add_ecdh_shares(&secp, &mut thread_rng(), &keys, ShareMode::Global)
            .map_err(|e| Error::msg(e.to_string()))?;
        psbt.commit_sp_outputs(&secp)
            .map_err(|e| Error::msg(e.to_string()))?;
        psbt.sign_silent_payment_inputs(&keys, &secp)
            .map_err(|e| Error::msg(e.to_string()))?;
        let psbt = Finalizer::new(psbt)
            .map_err(|e| Error::msg(e.to_string()))?
            .finalize(&secp)
            .map_err(|e| Error::msg(e.to_string()))?;
        let tx = Extractor::new(psbt)
            .map_err(|e| Error::msg(e.to_string()))?
            .extract_tx()
            .map_err(|e| Error::msg(e.to_string()))?;
        Ok(serialize(&tx).to_lower_hex_string())
    }

    /// Scan a signed transaction for silent-payment outputs belonging to this wallet.
    ///
    /// [prevout_scripts] must be the funding scriptPubKeys of each input, in vin order.
    /// Those scripts are not in the raw transaction; they come from the spent UTXOs.
    #[flutter_rust_bridge::frb(sync)]
    pub fn scan_signed_tx(
        &self,
        tx_hex: String,
        prevout_scripts: Vec<Vec<u8>>,
    ) -> Result<Vec<OwnedOutput>> {
        let tx: Transaction = deserialize_hex(&tx_hex)
            .map_err(|e| Error::msg(format!("invalid transaction hex: {e}")))?;

        if prevout_scripts.len() != tx.input.len() {
            return Err(Error::msg(format!(
                "prevout_scripts length {} does not match input count {}",
                prevout_scripts.len(),
                tx.input.len()
            )));
        }

        let secp = Secp256k1::new();
        let mut inputs = TransactionInputs::new();
        for (vin, (txin, script)) in tx.input.iter().zip(prevout_scripts.iter()).enumerate() {
            let outpoint = SpOutPoint::from_txid_and_vout(
                txin.previous_output.txid.to_string(),
                txin.previous_output.vout,
            )
            .map_err(|e| Error::msg(format!("input {vin} outpoint: {e}")))?;
            let witness: Vec<Vec<u8>> = txin.witness.to_vec();
            let pubkey = get_pubkey_from_input(txin.script_sig.as_bytes(), &witness, script)
                .map_err(|e| Error::msg(format!("input {vin} pubkey: {e}")))?;
            inputs.push(outpoint, script.clone(), pubkey);
        }

        let tweak_data = PublicTweakData::new(&secp, &inputs)
            .map_err(|e| Error::msg(format!("tweak data: {e}")))?;
        let shared_secret = TransactionSharedSecret::new_from_public_tweak_data(
            &secp,
            &tweak_data,
            &self.client.scan_key(),
        )
        .map_err(|e| Error::msg(format!("shared secret: {e}")))?;

        let output_keys: Vec<XOnlyPublicKey> = tx
            .output
            .iter()
            .filter(|o| o.script_pubkey.is_p2tr())
            .map(|o| {
                XOnlyPublicKey::from_slice(&o.script_pubkey.as_bytes()[2..])
                    .map_err(|e| Error::msg(format!("invalid p2tr output key: {e}")))
            })
            .collect::<Result<_>>()?;

        let ours = self
            .client
            .sp_receiver
            .scan_transaction(&shared_secret, &output_keys)
            .map_err(|e| Error::msg(format!("scan_transaction: {e}")))?;

        let txid = tx.compute_txid();
        let mut found = Vec::new();
        for (vout, txout) in tx.output.iter().enumerate() {
            if !txout.script_pubkey.is_p2tr() {
                continue;
            }
            let xonly = XOnlyPublicKey::from_slice(&txout.script_pubkey.as_bytes()[2..])?;
            for (label, map) in &ours {
                if let Some(tweak) = map.get(&xonly) {
                    found.push(OwnedOutput {
                        outpoint: ApiOutPoint {
                            txid: txid.to_string(),
                            vout: vout as u32,
                        },
                        tweak: tweak.to_be_bytes(),
                        amount: ApiAmount(txout.value.to_sat()),
                        script: txout.script_pubkey.to_bytes(),
                        label: label.as_ref().map(|l| l.as_inner().to_be_bytes()),
                    });
                    break;
                }
            }
        }

        Ok(found)
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::structs::input_selection::CoinSelectionStrategy;
    use crate::api::wallet::setup::{WalletSetupArgs, WalletSetupType};
    use psbt_v2::bitcoin::key::TapTweak;
    use psbt_v2::SpV0Info;
    use spdk_wallet::bitcoin::secp256k1::Scalar;
    use spdk_wallet::client::RecipientAddress;

    /// Deterministic test-vector mnemonic for the recipient wallet. Not a real
    /// wallet; do not send funds to it.
    /// Must stay in sync with `kTestRecipientSeed` in `lib/constants.dart`
    /// (duplicated: Rust unit tests cannot read Dart constants).
    const TEST_RECIPIENT_SEED: &str =
        "biology farm interest hub pull unique butter kangaroo spread demand tomato exercise";
    /// Deterministic sender: the canonical BIP-39 test mnemonic.
    const TEST_SENDER_SEED: &str =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    /// Payment codes derived from the seeds above on signet. Pinning them
    /// catches silent changes in key derivation or sp code encoding.
    const RECIPIENT_CODE: &str = "tsp1qq2d4vvramh9n3qrg5kaac7mjwdhfs402hg2msphmxuq3xqnw7hyj5qu9y636sf85v6uekr3vt3dcrzva64af9wct25y3wj0y4dgavjcp2uwsljny";
    const SENDER_CODE: &str = "tsp1qqdpels3srq45dlezqvk20t3dlueftry6p5thc7msjm0s6jm3g84jzq5rxzzunfck6d45va2jcqxk429agt3e4klf3vzmcgp3zqthryhhqgnz4k3n";

    const UTXO_SAT: u64 = 100_000;
    const SEND_SAT: u64 = 10_000;
    const FEE_SAT: u64 = 1_000;
    const CHANGE_SAT: u64 = UTXO_SAT - SEND_SAT - FEE_SAT;

    fn wallet(setup_type: WalletSetupType, network: Network) -> SpWallet {
        let setup = SpWallet::setup_wallet(WalletSetupArgs {
            setup_type,
            network: network.clone(),
        })
        .expect("setup wallet");
        SpWallet::new(
            setup.scan_key,
            setup.spend_key,
            network,
            setup.fingerprint,
            setup.derivation_path,
        )
        .expect("new wallet")
    }

    fn sender(network: Network) -> SpWallet {
        wallet(
            WalletSetupType::Mnemonic(TEST_SENDER_SEED.to_string()),
            network,
        )
    }

    fn recipient(network: Network) -> SpWallet {
        wallet(
            WalletSetupType::Mnemonic(TEST_RECIPIENT_SEED.to_string()),
            network,
        )
    }

    fn scalar(n: u8) -> Scalar {
        let mut bytes = [0u8; 32];
        bytes[31] = n;
        Scalar::from_be_bytes(bytes).expect("valid scalar")
    }

    /// A fake UTXO owned by `sender`: the output key is `spend + tweak`, as if
    /// discovered by scanning. Outpoints are deterministic and distinct per `n`.
    fn sender_utxo(sender: &SpWallet, value: u64, tweak: Scalar, n: u8) -> OwnedOutput {
        let secp = Secp256k1::new();
        let spend = sender.client.try_secret_spend_key().expect("secret spend");
        let sk = spend.add_tweak(&tweak).expect("tweak spend key");
        let (xonly, _) = sk.x_only_public_key(&secp);
        let script = ScriptBuf::new_p2tr_tweaked(xonly.dangerous_assume_tweaked());
        OwnedOutput {
            outpoint: ApiOutPoint {
                txid: format!("{:064x}", n),
                vout: n as u32,
            },
            tweak: tweak.to_be_bytes(),
            amount: ApiAmount(value),
            script: script.to_bytes(),
            label: None,
        }
    }

    fn single_payment_selection(utxos: &[OwnedOutput], sent: u64, fee: u64) -> InputSelection {
        let total: u64 = utxos.iter().map(|u| u.amount.0).sum();
        InputSelection {
            selected_utxos: utxos.iter().map(|u| u.outpoint.clone()).collect(),
            sent: ApiAmount(sent),
            n_sent_outputs: 1,
            change: ApiAmount(total - sent - fee),
            n_change_outputs: 1,
            fee: ApiAmount(fee),
            actual_fee_rate: 1.0,
            strategy: CoinSelectionStrategy::LowestFee,
        }
    }

    /// Deterministic end-to-end payment: one sender UTXO, one payment to the
    /// test recipient, one change output back to the sender's change code.
    fn pay_test_recipient(network: Network) -> (SpWallet, SpWallet, String, Vec<Vec<u8>>) {
        let sender = sender(network.clone());
        let recipient = recipient(network.clone());
        let utxo = sender_utxo(&sender, UTXO_SAT, scalar(1), 1);
        let prevout_scripts = vec![utxo.script.clone()];

        let created = sender
            .create_psbt(
                vec![utxo.clone()],
                vec![Recipient {
                    payment_code: recipient.get_receiving_address(),
                    amount: ApiAmount(SEND_SAT),
                }],
                single_payment_selection(&[utxo], SEND_SAT, FEE_SAT),
                network,
            )
            .expect("create psbt");

        let signed_hex = sender.sign_psbt(created.psbt).expect("sign psbt");
        (sender, recipient, signed_hex, prevout_scripts)
    }

    /// The BIP-375 PSBT_OUT_SP_V0_INFO payload for a payment code: scan key
    /// concatenated with spend key.
    fn sp_info(code: &str) -> SpV0Info {
        let code = match RecipientAddress::try_from(code.to_string()).expect("sp code") {
            RecipientAddress::SpCode(code) => code,
            _ => panic!("expected silent payment code"),
        };
        let mut info = [0u8; 66];
        info[..33].copy_from_slice(&code.scan_key().serialize());
        info[33..].copy_from_slice(&code.m_pubkey().serialize());
        info.into()
    }

    #[test]
    fn test_seed_payment_codes_are_pinned() {
        assert_eq!(
            recipient(Network::Signet).get_receiving_address(),
            RECIPIENT_CODE
        );
        assert_eq!(sender(Network::Signet).get_receiving_address(), SENDER_CODE);
    }

    /// BIP-376 updater role: every SP input must carry the per-output tweak in
    /// PSBT_IN_SP_TWEAK and an SP_SPEND_BIP32_DERIVATION keyed by the
    /// *untweaked* spend key B_spend (the signer applies the tweak itself).
    #[test]
    fn create_psbt_populates_bip376_input_fields() {
        let network = Network::Signet;
        let sender = sender(network.clone());
        let recipient = recipient(network.clone());
        let utxo = sender_utxo(&sender, UTXO_SAT, scalar(1), 1);

        let created = sender
            .create_psbt(
                vec![utxo.clone()],
                vec![Recipient {
                    payment_code: recipient.get_receiving_address(),
                    amount: ApiAmount(SEND_SAT),
                }],
                single_payment_selection(&[utxo.clone()], SEND_SAT, FEE_SAT),
                network,
            )
            .expect("create psbt");

        let psbt = Psbt::deserialize(&created.psbt).expect("psbt deserializes");
        assert_eq!(psbt.inputs.len(), 1);
        let input = &psbt.inputs[0];

        let witness_utxo = input.witness_utxo.as_ref().expect("witness utxo set");
        assert_eq!(witness_utxo.script_pubkey.to_bytes(), utxo.script);
        assert_eq!(witness_utxo.value.to_sat(), UTXO_SAT);
        assert_eq!(
            input.sp_tweak,
            Some(utxo.tweak),
            "PSBT_IN_SP_TWEAK must carry the per-output tweak"
        );

        let secp = Secp256k1::new();
        let b_spend = sender.client.try_secret_spend_key().expect("spend key");
        let (fingerprint, path) = sender.psbt_key_source().expect("key source");
        let (map_key, map_fingerprint, map_path) = input
            .get_sp_spend_bip32_derivation()
            .expect("SP spend derivation set");
        assert_eq!(
            map_key.serialize(),
            b_spend.public_key(&secp).serialize(),
            "BIP-376: the map key must be the untweaked spend key B_spend"
        );
        assert_eq!(map_fingerprint.to_string(), fingerprint.to_string());
        assert_eq!(map_path.to_string(), path.to_string());
    }

    /// BIP-375 constructor role: SP outputs carry an empty scriptPubKey plus
    /// PSBT_OUT_SP_V0_INFO (scan key || spend key) until signing time.
    #[test]
    fn create_psbt_populates_bip375_output_fields() {
        let network = Network::Signet;
        let sender = sender(network.clone());
        let recipient = recipient(network.clone());
        let utxo = sender_utxo(&sender, UTXO_SAT, scalar(1), 1);

        let created = sender
            .create_psbt(
                vec![utxo.clone()],
                vec![Recipient {
                    payment_code: recipient.get_receiving_address(),
                    amount: ApiAmount(SEND_SAT),
                }],
                single_payment_selection(&[utxo.clone()], SEND_SAT, FEE_SAT),
                network,
            )
            .expect("create psbt");

        let psbt = Psbt::deserialize(&created.psbt).expect("psbt deserializes");
        assert_eq!(psbt.outputs.len(), 2, "payment plus change");

        let payment_info = sp_info(&recipient.get_receiving_address());
        let change_info = sp_info(&sender.get_change_address());
        let mut seen = [false; 2];
        for output in &psbt.outputs {
            assert!(
                output.script_pubkey.is_empty(),
                "BIP-375: script must be unset until the signer computes it"
            );
            match output.sp_v0_info {
                Some(info) if info == payment_info => seen[0] = true,
                Some(info) if info == change_info => seen[1] = true,
                other => panic!("unexpected output sp_v0_info: {other:?}"),
            }
        }
        assert!(seen[0] && seen[1], "expected one payment and one change output");
    }

    #[test]
    fn create_psbt_rejects_inconsistent_selection() {
        let network = Network::Signet;
        let sender = sender(network.clone());
        let recipient = recipient(network.clone());
        let utxo = sender_utxo(&sender, UTXO_SAT, scalar(1), 1);
        let recipients = || {
            vec![Recipient {
                payment_code: recipient.get_receiving_address(),
                amount: ApiAmount(SEND_SAT),
            }]
        };

        let mut selection = single_payment_selection(&[utxo.clone()], SEND_SAT, FEE_SAT);
        selection.sent = ApiAmount(SEND_SAT + 1);
        let err = sender
            .create_psbt(vec![utxo.clone()], recipients(), selection, network.clone())
            .expect_err("amount mismatch must fail");
        assert!(err.to_string().contains("Amount mismatch"), "{err}");

        let mut selection = single_payment_selection(&[utxo.clone()], SEND_SAT, FEE_SAT);
        selection.n_sent_outputs = 2;
        let err = sender
            .create_psbt(vec![utxo.clone()], recipients(), selection, network.clone())
            .expect_err("count mismatch must fail");
        assert!(
            err.to_string().contains("Number of outputs mismatch"),
            "{err}"
        );

        let mut selection = single_payment_selection(&[utxo.clone()], SEND_SAT, FEE_SAT);
        selection.selected_utxos = vec![ApiOutPoint {
            txid: "ff".repeat(32),
            vout: 99,
        }];
        let err = sender
            .create_psbt(vec![utxo.clone()], recipients(), selection, network)
            .expect_err("unknown outpoint must fail");
        assert!(err.to_string().contains("not found"), "{err}");
    }

    #[test]
    fn create_psbt_rejects_wrong_network_code() {
        let sender = sender(Network::Signet);
        let mainnet_recipient = recipient(Network::Mainnet);
        let utxo = sender_utxo(&sender, UTXO_SAT, scalar(1), 1);

        let err = sender
            .create_psbt(
                vec![utxo.clone()],
                vec![Recipient {
                    payment_code: mainnet_recipient.get_receiving_address(),
                    amount: ApiAmount(SEND_SAT),
                }],
                single_payment_selection(&[utxo], SEND_SAT, FEE_SAT),
                Network::Signet,
            )
            .expect_err("mainnet code on signet must fail");
        assert!(err.to_string().contains("Wrong network"), "{err}");
    }

    #[test]
    fn scan_signed_tx_rejects_malformed_args() {
        let wallet = recipient(Network::Signet);

        let err = wallet
            .scan_signed_tx("zz".to_string(), vec![])
            .expect_err("invalid hex must fail");
        assert!(err.to_string().contains("invalid transaction hex"), "{err}");

        // minimal valid tx: version 2, one null input, no outputs
        let one_input_tx = concat!(
            "02000000", "01",
            "0000000000000000000000000000000000000000000000000000000000000000",
            "00000000", "00", "ffffffff",
            "00",
            "00000000"
        );
        let err = wallet
            .scan_signed_tx(one_input_tx.to_string(), vec![])
            .expect_err("prevout count mismatch must fail");
        assert!(
            err.to_string().contains("does not match input count"),
            "{err}"
        );
    }

    #[test]
    fn signed_payment_to_test_seed_is_detected_by_recipient() {
        let (_, recipient, signed_hex, prevout_scripts) = pay_test_recipient(Network::Signet);

        let tx: Transaction = deserialize_hex(&signed_hex).expect("signed tx deserializes");
        assert!(
            tx.input.iter().all(|i| !i.witness.is_empty()),
            "every input must be signed"
        );
        assert_eq!(tx.output.len(), 2, "payment plus change");
        assert!(
            tx.output.iter().all(|o| o.script_pubkey.is_p2tr()),
            "silent payment outputs must be p2tr"
        );
        assert_eq!(
            tx.output
                .iter()
                .filter(|o| o.value.to_sat() == SEND_SAT)
                .count(),
            1,
            "exactly one output should carry the payment amount"
        );

        let found = recipient
            .scan_signed_tx(signed_hex, prevout_scripts)
            .expect("recipient scan");

        assert_eq!(
            found.len(),
            1,
            "recipient should detect the payment and not the sender's change"
        );
        assert_eq!(found[0].amount.0, SEND_SAT);
        assert!(
            found[0].label.is_none(),
            "payment to the receiving code is unlabeled"
        );
        assert!(
            tx.output
                .iter()
                .any(|o| o.script_pubkey.as_bytes() == found[0].script
                    && o.value.to_sat() == SEND_SAT),
            "detected script/amount must match a transaction output"
        );
    }

    /// BIP-375 signer role: with silent payment outputs present, every
    /// signature must use SIGHASH_ALL (0x01).
    #[test]
    fn signatures_commit_to_all_outputs() {
        let (_, _, signed_hex, _) = pay_test_recipient(Network::Signet);
        let tx: Transaction = deserialize_hex(&signed_hex).expect("signed tx");
        for (vin, input) in tx.input.iter().enumerate() {
            let witness = input.witness.to_vec();
            assert_eq!(
                witness.len(),
                1,
                "input {vin}: key-path spend has one witness element"
            );
            let sig = &witness[0];
            // BIP-375 requires SIGHASH_ALL when SP outputs are present. Per
            // BIP-341 a 64-byte signature is SIGHASH_DEFAULT, which commits to
            // all outputs identically to SIGHASH_ALL, so both serializations
            // are accepted here (matching the BIP-375 reference validator,
            // which only polices the PSBT_IN_SIGHASH_TYPE field, not the sig
            // bytes). Any other sighash must be appended as a 65th byte and is
            // rejected.
            assert!(
                sig.len() == 64 || (sig.len() == 65 && sig[64] == 0x01),
                "input {vin}: signature must commit to all outputs (SIGHASH_DEFAULT or explicit SIGHASH_ALL), got len {} byte {:?}",
                sig.len(),
                sig.get(64),
            );
        }
    }

    #[test]
    fn multi_input_payment_is_detected_by_recipient() {
        let network = Network::Signet;
        let sender = sender(network.clone());
        let recipient = recipient(network.clone());
        let utxo1 = sender_utxo(&sender, UTXO_SAT, scalar(1), 1);
        let utxo2 = sender_utxo(&sender, 50_000, scalar(2), 2);
        let prevout_scripts = vec![utxo1.script.clone(), utxo2.script.clone()];

        let created = sender
            .create_psbt(
                vec![utxo1.clone(), utxo2.clone()],
                vec![Recipient {
                    payment_code: recipient.get_receiving_address(),
                    amount: ApiAmount(SEND_SAT),
                }],
                single_payment_selection(&[utxo1, utxo2], SEND_SAT, FEE_SAT),
                network,
            )
            .expect("create psbt");
        let signed_hex = sender.sign_psbt(created.psbt).expect("sign psbt");

        let tx: Transaction = deserialize_hex(&signed_hex).expect("signed tx");
        assert_eq!(tx.input.len(), 2);
        assert!(
            tx.input.iter().all(|i| !i.witness.is_empty()),
            "both inputs signed"
        );

        let found = recipient
            .scan_signed_tx(signed_hex, prevout_scripts)
            .expect("recipient scan");
        assert_eq!(
            found.len(),
            1,
            "recipient detects the payment across a multi-input tx"
        );
        assert_eq!(found[0].amount.0, SEND_SAT);
    }

    /// The sender detects its own change (via the labeled change code) but not
    /// the payment, which is bound to the recipient's scan key.
    #[test]
    fn sender_detects_own_change_as_labeled() {
        let (sender, _, signed_hex, prevout_scripts) = pay_test_recipient(Network::Signet);
        let found = sender
            .scan_signed_tx(signed_hex, prevout_scripts)
            .expect("sender scan");
        assert_eq!(
            found.len(),
            1,
            "sender should detect exactly its change output"
        );
        assert_eq!(found[0].amount.0, CHANGE_SAT);
        assert!(
            found[0].label.is_some(),
            "change uses the labeled change code"
        );
    }

    #[test]
    fn unrelated_wallet_does_not_detect_test_seed_payment() {
        let network = Network::Signet;
        let (_, _, signed_hex, prevout_scripts) = pay_test_recipient(network.clone());
        let stranger = wallet(WalletSetupType::NewWallet, network);

        let found = stranger
            .scan_signed_tx(signed_hex, prevout_scripts)
            .expect("stranger scan");
        assert!(
            found.is_empty(),
            "a wallet that is not the recipient must not detect the payment"
        );
    }
}
