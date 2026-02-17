use std::str::FromStr;

use spdk_core::{
    bitcoin::secp256k1::{PublicKey, SecretKey},
    SpendKey,
};

use crate::api::structs::network::Network;
use crate::wallet::derive_keys_from_seed;

use super::{ApiScanKey, ApiSpendKey, SpWallet};
use anyhow::Result;

/// we don't add a passphrase to the bip39 mnemonic
const PASSPHRASE: &str = "";

pub struct WalletSetupArgs {
    pub setup_type: WalletSetupType,
    pub network: Network,
}

pub enum WalletSetupType {
    NewWallet,
    Mnemonic(String),
    Full(String, String),
    WatchOnly(String, String),
}

pub struct WalletSetupResult {
    pub mnemonic: Option<String>,
    pub scan_key: ApiScanKey,
    pub spend_key: ApiSpendKey,
}

impl SpWallet {
    #[flutter_rust_bridge::frb(sync)]
    pub fn setup_wallet(setup_args: WalletSetupArgs) -> Result<WalletSetupResult> {
        let WalletSetupArgs {
            setup_type,
            network,
        } = setup_args;

        match setup_type {
            WalletSetupType::NewWallet => {
                // We create a new wallet and return the new mnemonic
                let m = bip39::Mnemonic::generate(12)?;
                let seed = m.to_seed(PASSPHRASE);
                let (scan_sk, spend_sk) = derive_keys_from_seed(&seed, network.into())?;

                let scan_key = ApiScanKey(scan_sk);
                let spend_key = ApiSpendKey(SpendKey::Secret(spend_sk));

                Ok(WalletSetupResult {
                    mnemonic: Some(m.to_string()),
                    scan_key,
                    spend_key,
                })
            }
            WalletSetupType::Mnemonic(mnemonic) => {
                // We restore from seed
                let m = bip39::Mnemonic::from_str(&mnemonic)?;
                let seed = m.to_seed(PASSPHRASE);
                let (scan_sk, spend_sk) = derive_keys_from_seed(&seed, network.into())?;

                let scan_key = ApiScanKey(scan_sk);
                let spend_key = ApiSpendKey(SpendKey::Secret(spend_sk));

                Ok(WalletSetupResult {
                    mnemonic: Some(mnemonic),
                    scan_key,
                    spend_key,
                })
            }
            WalletSetupType::Full(scan_sk_hex, spend_sk_hex) => {
                let scan_sk = SecretKey::from_str(&scan_sk_hex)?;
                let spend_sk = SecretKey::from_str(&spend_sk_hex)?;

                let scan_key = ApiScanKey(scan_sk);
                let spend_key = ApiSpendKey(SpendKey::Secret(spend_sk));

                Ok(WalletSetupResult {
                    mnemonic: None,
                    scan_key,
                    spend_key,
                })
            }
            WalletSetupType::WatchOnly(scan_sk_hex, spend_pk_hex) => {
                let scan_sk = SecretKey::from_str(&scan_sk_hex)?;
                let spend_pk = PublicKey::from_str(&spend_pk_hex)?;

                let scan_key = ApiScanKey(scan_sk);
                let spend_key = ApiSpendKey(SpendKey::Public(spend_pk));

                Ok(WalletSetupResult {
                    mnemonic: None,
                    scan_key,
                    spend_key,
                })
            }
        }
    }
}
