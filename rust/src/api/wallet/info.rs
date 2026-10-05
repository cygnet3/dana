use std::str::FromStr;

use flutter_rust_bridge::frb;
use spdk_wallet::bitcoin::{
    key::Secp256k1, CompressedPublicKey, Network as BitcoinNetwork, PrivateKey,
};
use spdk_wallet::client::SpendKey;
use spdk_wallet::silentpayments::Network as SpNetwork;

use crate::api::structs::network::Network;

use super::SpWallet;
use sp_descriptor::{
    DescriptorPublicKey, DescriptorSecretKey, DescriptorSpendKey, Sp, SpKey, SpScanKey, SpSpendKey,
};

impl SpWallet {
    #[frb(sync)]
    pub fn get_receiving_address(&self) -> String {
        self.client.receiving_code().to_string()
    }

    #[frb(sync)]
    pub fn get_change_address(&self) -> String {
        self.client.change_code().to_string()
    }

    #[frb(sync)]
    pub fn get_network(&self) -> Network {
        self.client.network().into()
    }

    #[frb(sync)]
    pub fn get_encoded_descriptor_watch_only(&self) -> String {
        let spend_key = match self.get_spend_key().0 {
            SpendKey::Secret(sk) => sk,
            _ => unreachable!(),
        };
        let spend_pk = CompressedPublicKey(spend_key.public_key(&Secp256k1::signing_only()));

        let network: BitcoinNetwork = self.get_network().into();
        let sp_network = SpNetwork::try_from(network.to_core_arg()).unwrap();
        let sp_scan_key = SpScanKey {
            scan_key: self.get_scan_key().0,
            spend_key: spend_pk,
            network: sp_network,
        };
        let encoded_key: SpKey = SpKey::Scan(sp_scan_key);
        let encoded_descriptor = Sp::from_sp_key(encoded_key);

        format!("{}", encoded_descriptor)
    }

    #[frb(sync)]
    pub fn get_encoded_descriptor(&self) -> String {
        let spend_key = match self.get_spend_key().0 {
            SpendKey::Secret(sk) => sk,
            _ => unreachable!(),
        };

        let network: BitcoinNetwork = self.get_network().into();
        let sp_network = SpNetwork::try_from(network.to_core_arg()).unwrap();
        let sp_spend_key = SpSpendKey {
            scan_key: self.get_scan_key().0,
            spend_key,
            network: sp_network,
        };
        let encoded_key: SpKey = SpKey::Spend(sp_spend_key);
        let encoded_descriptor = Sp::from_sp_key(encoded_key);

        format!("{}", encoded_descriptor)
    }

    #[frb(sync)]
    pub fn get_two_key_descriptor_watch_only(&self) -> String {
        let network: BitcoinNetwork = self.get_network().into();

        let scan_wif = PrivateKey::new(self.get_scan_key().0, network).to_wif();
        let scan_desc = DescriptorSecretKey::from_str(&scan_wif).unwrap();

        let spend_pk = match self.get_spend_key().0 {
            SpendKey::Secret(sk) => sk.public_key(&Secp256k1::signing_only()),
            SpendKey::Public(pk) => pk,
        };
        let spend_desc = DescriptorSpendKey::Public(
            DescriptorPublicKey::from_str(&spend_pk.to_string()).unwrap(),
        );

        let descriptor = Sp::from_keys(scan_desc, spend_desc).unwrap();
        format!("{}", descriptor)
    }

    #[frb(sync)]
    pub fn get_two_key_descriptor(&self) -> String {
        let network: BitcoinNetwork = self.get_network().into();

        let scan_wif = PrivateKey::new(self.get_scan_key().0, network).to_wif();
        let scan_desc = DescriptorSecretKey::from_str(&scan_wif).unwrap();

        let spend_desc = match self.get_spend_key().0 {
            SpendKey::Secret(sk) => {
                let spend_wif = PrivateKey::new(sk, network).to_wif();
                DescriptorSpendKey::Private(DescriptorSecretKey::from_str(&spend_wif).unwrap())
            }
            _ => unreachable!(),
        };

        let descriptor = Sp::from_keys(scan_desc, spend_desc).unwrap();
        format!("{}", descriptor)
    }
}
