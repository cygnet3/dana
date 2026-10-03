use anyhow::Result;
use flutter_rust_bridge::frb;
use spdk_wallet::client::RecipientAddress;
use spdk_wallet::silentpayments::Network as SpNetwork;

use crate::api::structs::network::Network;

#[frb(sync)]
pub fn validate_address_with_network(address: String, network: Network) -> Result<()> {
    log::debug!(
        "address_with_network: address: {}, network: {:?}",
        address,
        network
    );
    let address = RecipientAddress::try_from(address);

    match address {
        Ok(RecipientAddress::LegacyAddress(legacy_address)) => {
            legacy_address.require_network(network.into())?;
            Ok(())
        }
        Ok(RecipientAddress::SpCode(sp_address)) => match (sp_address.network(), &network) {
            (SpNetwork::Mainnet, Network::Mainnet)
            | (SpNetwork::Testnet, Network::Testnet3)
            | (SpNetwork::Testnet, Network::Testnet4)
            | (SpNetwork::Testnet, Network::Signet)
            | (SpNetwork::Regtest, Network::Regtest) => Ok(()),
            (sp_network, _) => Err(anyhow::anyhow!(
                "Wrong network, expected: {:?}, got: {:?}",
                network,
                sp_network,
            )),
        },
        Ok(RecipientAddress::Data(_)) => {
            Err(anyhow::Error::msg("Sending to OP_RETURN not allowed"))
        }
        Err(e) => Err(e),
    }
}

#[frb(sync)]
pub fn is_reusable_payment_code(address: String) -> bool {
    matches!(
        RecipientAddress::try_from(address),
        Ok(RecipientAddress::SpCode(_))
    )
}

#[frb(sync)]
pub fn sanitize_payment_code(address: String) -> Result<String> {
    Ok(RecipientAddress::try_from(address)?.into())
}

#[cfg(test)]
mod tests {
    use spdk_wallet::bitcoin::secp256k1::{Secp256k1, SecretKey};
    use spdk_wallet::bitcoin::{Address, Network as BtcNetwork, PublicKey};
    use spdk_wallet::silentpayments::{Network as SpNetwork, SilentPaymentCode};

    use super::*;

    fn legacy_address(network: BtcNetwork) -> Address {
        let secp = Secp256k1::new();
        let pk = PublicKey::new(
            SecretKey::from_slice(&[0x07; 32])
                .unwrap()
                .public_key(&secp),
        );
        Address::p2pkh(pk, network)
    }

    fn sp_address(network: SpNetwork) -> SilentPaymentCode {
        let secp = Secp256k1::new();
        let scan = SecretKey::from_slice(&[0x01; 32])
            .unwrap()
            .public_key(&secp);
        let spend = SecretKey::from_slice(&[0x02; 32])
            .unwrap()
            .public_key(&secp);
        SilentPaymentCode::new_v0(scan, spend, network)
    }

    mod validate_address_with_network_tests {
        use super::*;

        #[test]
        fn accepts_legacy_address_on_matching_network() {
            let address = legacy_address(BtcNetwork::Bitcoin).to_string();
            assert!(validate_address_with_network(address, Network::Mainnet).is_ok());
        }

        #[test]
        fn rejects_legacy_address_on_wrong_network() {
            let address = legacy_address(BtcNetwork::Bitcoin).to_string();
            assert!(validate_address_with_network(address, Network::Testnet3).is_err());
        }

        // Legacy Base58 addresses can't distinguish testnet/testnet4/signet/regtest
        // from one another (they all share the same version byte), only mainnet vs. not.
        #[test]
        fn legacy_testnet_address_is_accepted_on_every_test_like_network() {
            let address = legacy_address(BtcNetwork::Testnet).to_string();
            for network in [
                Network::Testnet3,
                Network::Testnet4,
                Network::Signet,
                Network::Regtest,
            ] {
                assert!(
                    validate_address_with_network(address.clone(), network.clone()).is_ok(),
                    "expected {address} to be valid for {network:?}"
                );
            }
        }

        #[test]
        fn accepts_sp_mainnet_on_mainnet() {
            let address = sp_address(SpNetwork::Mainnet).to_string();
            assert!(validate_address_with_network(address, Network::Mainnet).is_ok());
        }

        #[test]
        fn accepts_sp_testnet_on_testnet3_testnet4_and_signet() {
            let address = sp_address(SpNetwork::Testnet).to_string();
            for network in [Network::Testnet3, Network::Testnet4, Network::Signet] {
                assert!(
                    validate_address_with_network(address.clone(), network.clone()).is_ok(),
                    "expected {address} to be valid for {network:?}"
                );
            }
        }

        #[test]
        fn accepts_sp_regtest_on_regtest() {
            let address = sp_address(SpNetwork::Regtest).to_string();
            assert!(validate_address_with_network(address, Network::Regtest).is_ok());
        }

        #[test]
        fn rejects_sp_regtest_on_testnet() {
            let address = sp_address(SpNetwork::Regtest).to_string();
            assert!(validate_address_with_network(address, Network::Testnet3).is_err());
        }

        #[test]
        fn rejects_sp_mainnet_on_testnet() {
            let address = sp_address(SpNetwork::Mainnet).to_string();
            let err = validate_address_with_network(address, Network::Testnet3).unwrap_err();
            assert!(
                err.to_string().contains("Wrong network"),
                "unexpected: {err}"
            );
        }

        #[test]
        fn rejects_unparseable_address() {
            assert!(validate_address_with_network(
                "not-an-address!!".to_string(),
                Network::Mainnet
            )
            .is_err());
        }
    }

    mod is_reusable_payment_code_tests {
        use super::*;

        #[test]
        fn true_for_sp_address() {
            let address = sp_address(SpNetwork::Mainnet).to_string();
            assert!(is_reusable_payment_code(address));
        }

        #[test]
        fn false_for_legacy_address() {
            let address = legacy_address(BtcNetwork::Bitcoin).to_string();
            assert!(!is_reusable_payment_code(address));
        }

        #[test]
        fn false_for_op_return_data() {
            assert!(!is_reusable_payment_code("deadbeef".to_string()));
        }

        #[test]
        fn false_for_invalid_input() {
            assert!(!is_reusable_payment_code("not-an-address!!".to_string()));
        }
    }

    mod sanitize_payment_code_tests {
        use super::*;

        #[test]
        fn legacy_address_roundtrips_unchanged() {
            let address = legacy_address(BtcNetwork::Bitcoin).to_string();
            assert_eq!(sanitize_payment_code(address.clone()).unwrap(), address);
        }

        #[test]
        fn uppercase_sp_address_is_lowercased() {
            let address = sp_address(SpNetwork::Mainnet).to_string();
            let uppercased = address.to_uppercase();
            assert_eq!(sanitize_payment_code(uppercased).unwrap(), address);
        }

        #[test]
        fn op_return_hex_is_lowercased_without_script_wrapping() {
            let sanitized = sanitize_payment_code("DEADBEEF".to_string()).unwrap();
            // Must stay the raw payload, not get wrapped in an OP_RETURN script
            // (which would prepend opcode/pushdata framing bytes).
            assert_eq!(sanitized, "deadbeef");
        }

        #[test]
        fn is_idempotent_for_every_variant() {
            let inputs = [
                legacy_address(BtcNetwork::Bitcoin).to_string(),
                sp_address(SpNetwork::Mainnet).to_string().to_uppercase(),
                "DEADBEEF".to_string(),
            ];
            for raw in inputs {
                let once = sanitize_payment_code(raw).unwrap();
                let twice = sanitize_payment_code(once.clone()).unwrap();
                assert_eq!(once, twice, "sanitize_payment_code is not idempotent");
            }
        }

        #[test]
        fn rejects_invalid_input() {
            assert!(sanitize_payment_code("not-an-address!!".to_string()).is_err());
        }
    }
}
