use std::{collections::HashMap, str::FromStr};

use crate::api::structs::network::Network;
use crate::api::structs::owned_output::ApiOwnedOutput;
use crate::api::structs::recipient::ApiRecipient;
use crate::api::structs::unsigned_transaction::ApiSilentPaymentUnsignedTransaction;

use anyhow::Result;
use backend_blindbit_v1::BlindbitClient;
use bip39::rand::{thread_rng, RngCore};
use spdk_core::{
    bitcoin::{consensus::serialize, hex::DisplayHex, OutPoint},
    FeeRate, OwnedOutput, Recipient, RecipientAddress, SpClient,
};

use super::SpWallet;

impl SpWallet {
    #[flutter_rust_bridge::frb(sync)]
    pub fn create_new_transaction(
        &self,
        api_outputs: HashMap<String, ApiOwnedOutput>,
        api_recipients: Vec<ApiRecipient>,
        feerate: f32,
        network: Network,
    ) -> Result<ApiSilentPaymentUnsignedTransaction> {
        let client = &self.client;
        let available_utxos: Result<Vec<(OutPoint, OwnedOutput)>> = api_outputs
            .into_iter()
            .map(|(string, output)| {
                let outpoint = OutPoint::from_str(&string)?;
                Ok((outpoint, output.into()))
            })
            .collect();
        let recipients: Vec<Recipient> = api_recipients
            .into_iter()
            .map(|r| r.try_into().unwrap())
            .collect();
        let res = client.create_new_transaction(
            available_utxos?,
            recipients,
            FeeRate::from_sat_per_vb(feerate),
            network.into(),
        )?;

        Ok(res.into())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn create_drain_transaction(
        &self,
        api_outputs: HashMap<String, ApiOwnedOutput>,
        wipe_address: String,
        feerate: f32,
        network: Network,
    ) -> Result<ApiSilentPaymentUnsignedTransaction> {
        let client = &self.client;
        let available_utxos: Result<Vec<(OutPoint, OwnedOutput)>> = api_outputs
            .into_iter()
            .map(|(string, output)| {
                let outpoint = OutPoint::from_str(&string)?;
                Ok((outpoint, output.into()))
            })
            .collect();

        let recipient_address: RecipientAddress = RecipientAddress::try_from(wipe_address)?;
        let res = client.create_drain_transaction(
            available_utxos?,
            recipient_address,
            FeeRate::from_sat_per_vb(feerate),
            network.into(),
        )?;

        Ok(res.into())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn sign_transaction(
        &self,
        unsigned_transaction: ApiSilentPaymentUnsignedTransaction,
    ) -> Result<String> {
        let mut aux_rand = [0u8; 32];

        let mut rng = thread_rng();
        rng.fill_bytes(&mut aux_rand);

        let client = &self.client;
        let tx = client.sign_transaction(unsigned_transaction.into(), &aux_rand)?;
        Ok(serialize(&tx).to_lower_hex_string())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn finalize_transaction(
        unsigned_transaction: ApiSilentPaymentUnsignedTransaction,
    ) -> Result<ApiSilentPaymentUnsignedTransaction> {
        let res = SpClient::finalize_transaction(unsigned_transaction.into())?;
        Ok(res.into())
    }

    // note: should only be used when using regtest, else there is privacy loss!
    pub async fn broadcast_using_blindbit(blindbit_url: String, tx: String) -> Result<String> {
        let blindbit_client = BlindbitClient::new(blindbit_url)?;

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
