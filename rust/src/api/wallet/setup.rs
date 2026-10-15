use std::str::FromStr;

use bip392::Sp;
use spdk_wallet::bitcoin::secp256k1::{PublicKey, SecretKey};
use spdk_wallet::client::SpendKey;

use crate::api::structs::network::Network;
use crate::wallet::derive_keys_from_seed;

use super::{ApiScanKey, ApiSpendKey, SpWallet};
use anyhow::{bail, Result};

/// we don't add a passphrase to the bip39 mnemonic
const PASSPHRASE: &str = "";

pub struct WalletSetupArgs {
    pub setup_type: WalletSetupType,
    pub network: Network,
}

pub enum WalletSetupType {
    NewWallet,
    Mnemonic(String),
    /// An `sp()` descriptor that includes the spend private key.
    Descriptor(String),
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
            WalletSetupType::Descriptor(descriptor) => {
                let compact: String = descriptor.chars().filter(|c| !c.is_whitespace()).collect();
                if compact.is_empty() {
                    bail!("Descriptor is empty");
                }

                let sp = Sp::from_str(&compact)
                    .map_err(|e| anyhow::anyhow!("Invalid descriptor: {e}"))?;

                let descriptor_is_mainnet = sp.is_mainnet();
                if descriptor_is_mainnet != matches!(network, Network::Mainnet) {
                    bail!(
                        "This descriptor is for {}, but this wallet is on {}.",
                        if descriptor_is_mainnet {
                            "mainnet"
                        } else {
                            "a test network"
                        },
                        Into::<&str>::into(network),
                    );
                }

                let Some(spend_secret) = sp.spend_secret() else {
                    bail!(
                        "This descriptor has no spend private key. Paste a descriptor that can spend."
                    );
                };

                Ok(WalletSetupResult {
                    mnemonic: None,
                    scan_key: ApiScanKey(sp.scan_key()),
                    spend_key: ApiSpendKey(SpendKey::Secret(spend_secret)),
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

#[cfg(test)]
mod tests {
    use bip392::{
        DescriptorPublicKey, DescriptorSecretKey, DescriptorSpendKey, Sp, SpKey, SpScanKey,
        SpSpendKey,
    };
    use spdk_wallet::bitcoin::bip32::{DerivationPath, Xpriv, Xpub};
    use spdk_wallet::bitcoin::key::Secp256k1;
    use spdk_wallet::bitcoin::{Network as BitcoinNetwork, NetworkKind, PrivateKey};
    use spdk_wallet::silentpayments::Network as SpNetwork;

    use super::*;

    fn path(s: &str) -> DerivationPath {
        s.parse().unwrap()
    }

    fn keypair() -> (SecretKey, SecretKey) {
        (
            SecretKey::from_slice(&[0x11; 32]).unwrap(),
            SecretKey::from_slice(&[0x22; 32]).unwrap(),
        )
    }

    fn encoded(full: bool, network: SpNetwork) -> String {
        let (scan, spend) = keypair();
        let key = if full {
            SpKey::Spend(SpSpendKey {
                scan_key: scan,
                spend_key: spend,
                network,
            })
        } else {
            let spend_pk = spend.public_key(&Secp256k1::signing_only());
            SpKey::Scan(SpScanKey {
                scan_key: scan,
                spend_key: spend_pk,
                network,
            })
        };
        Sp::from_sp_key(key).to_string()
    }

    fn two_key(full: bool, network: BitcoinNetwork) -> String {
        let (scan, spend) = keypair();
        let scan_desc =
            DescriptorSecretKey::from_str(&PrivateKey::new(scan, network).to_wif()).unwrap();
        let spend_desc = if full {
            let spend_wif = PrivateKey::new(spend, network).to_wif();
            DescriptorSpendKey::Private(DescriptorSecretKey::from_str(&spend_wif).unwrap())
        } else {
            let pk = spend.public_key(&Secp256k1::signing_only());
            DescriptorSpendKey::Public(DescriptorPublicKey::from_str(&pk.to_string()).unwrap())
        };
        Sp::from_keys(scan_desc, spend_desc).unwrap().to_string()
    }

    fn restore(descriptor: &str, network: Network) -> Result<WalletSetupResult> {
        SpWallet::setup_wallet(WalletSetupArgs {
            setup_type: WalletSetupType::Descriptor(descriptor.to_string()),
            network,
        })
    }

    #[test]
    fn restores_encoded_full_descriptor() {
        let (scan, spend) = keypair();
        let result = restore(&encoded(true, SpNetwork::Mainnet), Network::Mainnet).unwrap();
        assert!(result.mnemonic.is_none());
        assert_eq!(result.scan_key.0, scan);
        assert_eq!(result.spend_key.0, SpendKey::Secret(spend));
    }

    #[test]
    fn rejects_encoded_watch_only_descriptor() {
        let err = error_message(encoded(false, SpNetwork::Mainnet), Network::Mainnet);
        assert!(err.contains("no spend private key"), "{err}");
    }

    #[test]
    fn rejects_two_key_watch_only_descriptor() {
        let err = error_message(two_key(false, BitcoinNetwork::Signet), Network::Signet);
        assert!(err.contains("no spend private key"), "{err}");
    }

    #[test]
    fn restores_two_key_descriptor_ignoring_whitespace() {
        let (scan, spend) = keypair();
        let descriptor = two_key(true, BitcoinNetwork::Signet);
        let spaced = descriptor
            .chars()
            .flat_map(|c| [c, '\n'])
            .collect::<String>();
        let result = restore(&spaced, Network::Signet).unwrap();
        assert_eq!(result.scan_key.0, scan);
        assert_eq!(result.spend_key.0, SpendKey::Secret(spend));
    }

    fn error_message(descriptor: String, network: Network) -> String {
        match restore(&descriptor, network) {
            Err(err) => err.to_string(),
            Ok(_) => panic!("expected descriptor restore to fail"),
        }
    }

    #[test]
    fn rejects_mainnet_descriptor_on_signet() {
        let err = error_message(encoded(true, SpNetwork::Mainnet), Network::Signet);
        assert!(err.contains("mainnet"), "{err}");
    }

    #[test]
    fn rejects_signet_descriptor_on_mainnet() {
        let err = error_message(two_key(true, BitcoinNetwork::Signet), Network::Mainnet);
        assert!(err.contains("test network"), "{err}");
    }

    #[test]
    fn restores_bip352_xprv_descriptor() {
        let master = Xpriv::new_master(NetworkKind::Main, &[0x11; 64]).unwrap();
        let secp = Secp256k1::signing_only();
        let xprv = master.derive_priv(&secp, &path("m/352h/0h/0h")).unwrap();
        let expected_scan = master
            .derive_priv(&secp, &path("m/352h/0h/0h/1h/0"))
            .unwrap()
            .private_key;
        let expected_spend = master
            .derive_priv(&secp, &path("m/352h/0h/0h/0h/0"))
            .unwrap()
            .private_key;

        // Paths are relative to the account xprv, so this is the BIP-352 pair.
        let descriptor = format!("sp([deadbeef/352h/0h/0h]{xprv}/1h/0,{xprv}/0h/0)");
        let result = restore(&descriptor, Network::Mainnet).unwrap();
        assert!(result.mnemonic.is_none());
        assert_eq!(result.scan_key.0, expected_scan);
        assert_eq!(result.spend_key.0, SpendKey::Secret(expected_spend));
    }

    #[test]
    fn rejects_xprv_xpub_watch_only_descriptor() {
        let master = Xpriv::new_master(NetworkKind::Main, &[0x11; 64]).unwrap();
        let secp = Secp256k1::signing_only();
        let xprv = master.derive_priv(&secp, &path("m/352h/0h/0h")).unwrap();
        // The spend path's hardened step cannot be derived from an account xpub,
        // so the xpub is the key at m/352h/0h/0h/0h and the descriptor child is /0.
        let spend_parent = master.derive_priv(&secp, &path("m/352h/0h/0h/0h")).unwrap();
        let spend_xpub = Xpub::from_priv(&secp, &spend_parent);
        let descriptor =
            format!("sp([deadbeef/352h/0h/0h]{xprv}/1h/0,[deadbeef/352h/0h/0h/0h]{spend_xpub}/0)");

        let err = error_message(descriptor, Network::Mainnet);
        assert!(err.contains("no spend private key"), "{err}");
    }
}
