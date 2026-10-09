use std::str::FromStr;

use anyhow::Result;
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use spdk_wallet::bitcoin::address::NetworkUnchecked;
use spdk_wallet::bitcoin::{Address, AddressType};
use spdk_wallet::client::RecipientAddress as SpRecipientAddress;
use spdk_wallet::silentpayments::Network as SpNetwork;

use crate::api::structs::amount::Amount;
use crate::api::structs::network::Network;
use crate::api::structs::silent_payment_code::SilentPaymentCode;

/// How a [`PaymentCode`] is encoded.
///
/// OP_RETURN is not a kind: [`PaymentCode::parse`] rejects it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PaymentCodeKind {
    /// BIP352 `sp1` / `tsp1` / `sprt1`.
    SilentPayment,
    /// Bech32 or bech32m: segwit v0 (`bc1q`) or taproot (`bc1p`).
    Bech32,
    /// Base58Check P2PKH or P2SH.
    Base58,
}

/// A spend destination: silent payment, bech32/bech32m, or Base58Check.
///
/// Opaque to Dart. Construct with [`PaymentCode::parse`]. Bech32 and
/// bech32m input is stored lowercase; Base58Check case is preserved.
///
/// The inner value can still be an OP_RETURN output when it comes from the
/// wallet. [`PaymentCode::parse`] never produces one, and
/// [`PaymentCode::kind`] returns an error for it.
#[derive(Debug, Clone, PartialEq)]
#[frb(opaque)]
pub struct PaymentCode(SpRecipientAddress);

impl PaymentCode {
    /// Parse a silent payment code, segwit v0 address, taproot address, or
    /// Base58Check address. Segwit v0 and taproot share [`PaymentCodeKind::Bech32`].
    ///
    /// Rejects OP_RETURN payloads and anything else.
    #[frb(sync)]
    pub fn parse(address: String) -> Result<Self> {
        Self::parse_as_str(address.as_str())
    }

    pub(crate) fn parse_as_str(address: &str) -> Result<Self> {
        if let Ok(code) = SilentPaymentCode::parse_as_str(address) {
            return Ok(code.into());
        }

        let unchecked = Address::<NetworkUnchecked>::from_str(address)?;
        let checked = unchecked.assume_checked();
        match checked.address_type() {
            Some(
                AddressType::P2wpkh
                | AddressType::P2wsh
                | AddressType::P2tr
                | AddressType::P2pkh
                | AddressType::P2sh,
            ) => Ok(Self(SpRecipientAddress::LegacyAddress(
                checked.into_unchecked(),
            ))),
            Some(other) => Err(anyhow::anyhow!("unsupported address type: {other}")),
            None => Err(anyhow::anyhow!("unsupported address")),
        }
    }

    /// Canonical text form.
    ///
    /// Segwit, taproot, and silent payment codes are lowercase. Base58Check is unchanged.
    #[frb(sync)]
    pub fn encode(&self) -> String {
        String::from(self.0.clone())
    }

    #[frb(sync)]
    pub fn kind(&self) -> Result<PaymentCodeKind> {
        match &self.0 {
            SpRecipientAddress::SpCode(_) => Ok(PaymentCodeKind::SilentPayment),
            SpRecipientAddress::LegacyAddress(address) => {
                match address.assume_checked_ref().address_type() {
                    Some(AddressType::P2wpkh | AddressType::P2wsh | AddressType::P2tr) => {
                        Ok(PaymentCodeKind::Bech32)
                    }
                    Some(AddressType::P2pkh | AddressType::P2sh) => Ok(PaymentCodeKind::Base58),
                    Some(other) => Err(anyhow::anyhow!("unsupported address type: {other}")),
                    None => Err(anyhow::anyhow!("unsupported address")),
                }
            }
            SpRecipientAddress::Data(_) => Err(anyhow::anyhow!("OP_RETURN is not a payment code")),
        }
    }

    /// `None` unless this is a silent payment code.
    #[frb(sync)]
    pub fn silent_payment_code(&self) -> Option<SilentPaymentCode> {
        match &self.0 {
            SpRecipientAddress::SpCode(code) => Some(SilentPaymentCode::from(*code)),
            _ => None,
        }
    }

    /// Whether this address is valid for `network`.
    ///
    /// `tsp` and `tb` match testnet3, testnet4, and signet, not regtest.
    /// Base58 testnet version bytes also match regtest.
    #[frb(sync)]
    pub fn is_valid_for_network(&self, network: Network) -> bool {
        match &self.0 {
            SpRecipientAddress::SpCode(code) => match (code.network(), &network) {
                (SpNetwork::Mainnet, Network::Mainnet)
                | (SpNetwork::Testnet, Network::Testnet3)
                | (SpNetwork::Testnet, Network::Testnet4)
                | (SpNetwork::Testnet, Network::Signet)
                | (SpNetwork::Regtest, Network::Regtest) => true,
                _ => false,
            },
            SpRecipientAddress::LegacyAddress(address) => {
                address.is_valid_for_network(network.into())
            }
            SpRecipientAddress::Data(_) => false,
        }
    }

    #[frb(sync)]
    pub fn matches(&self, other: Self) -> bool {
        *self == other
    }
}

impl Serialize for PaymentCode {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.encode())
    }
}

impl<'de> Deserialize<'de> for PaymentCode {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        Self::parse(s).map_err(serde::de::Error::custom)
    }
}

impl From<SpRecipientAddress> for PaymentCode {
    fn from(value: SpRecipientAddress) -> Self {
        Self(value)
    }
}

impl From<PaymentCode> for SpRecipientAddress {
    fn from(value: PaymentCode) -> Self {
        value.0
    }
}

impl TryFrom<String> for PaymentCode {
    type Error = anyhow::Error;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        Self::parse(value)
    }
}

impl std::fmt::Display for PaymentCode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.encode())
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct Recipient {
    pub payment_code: PaymentCode,
    pub amount: Amount,
}

impl Recipient {
    #[frb(sync)]
    pub fn new(payment_code: PaymentCode, amount: Amount) -> Self {
        Self {
            payment_code,
            amount,
        }
    }
}

impl From<spdk_wallet::client::Recipient> for Recipient {
    fn from(value: spdk_wallet::client::Recipient) -> Self {
        Recipient {
            payment_code: value.address.into(),
            amount: value.amount.into(),
        }
    }
}

impl From<Recipient> for spdk_wallet::client::Recipient {
    fn from(value: Recipient) -> Self {
        Self {
            address: value.payment_code.into(),
            amount: value.amount.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SP_ADDRESS: &str = "sp1qq2xewwk5u02gxxurdzr6r6jerelncw82rlyvw2kpggxt3pum4kp6yq62utdcljdtmxpy3vs7c940hvjuzedhhsf7h2y5lflk7zp2xhgz3vryqw4n";
    const P2WPKH: &str = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4";
    const P2WSH: &str = "bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3";
    const TB_P2WPKH: &str = "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx";
    const P2PKH: &str = "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2";
    const P2SH: &str = "31h1vYVSYuKP6AhS86fbRdMw9XHieotbST";
    // rust-bitcoin mainnet P2TR vector.
    const P2TR: &str = "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr";

    #[test]
    fn parse_canonicalizes_uppercase_bech32_and_bech32m() {
        let sp = PaymentCode::parse(SP_ADDRESS.to_uppercase()).unwrap();
        assert_eq!(sp.encode(), SP_ADDRESS);
        assert_eq!(sp.kind().unwrap(), PaymentCodeKind::SilentPayment);
        assert!(sp.silent_payment_code().is_some());
        assert!(sp.is_valid_for_network(Network::Mainnet));
        assert!(!sp.is_valid_for_network(Network::Testnet3));

        let segwit = PaymentCode::parse(P2WPKH.to_uppercase()).unwrap();
        assert_eq!(segwit.encode(), P2WPKH);
        assert_eq!(segwit.kind().unwrap(), PaymentCodeKind::Bech32);
        assert!(segwit.silent_payment_code().is_none());
        assert!(segwit.is_valid_for_network(Network::Mainnet));
        assert!(!segwit.is_valid_for_network(Network::Testnet3));
    }

    #[test]
    fn classifies_segwit_v0_and_base58() {
        assert_eq!(
            PaymentCode::parse(P2WSH.to_string())
                .unwrap()
                .kind()
                .unwrap(),
            PaymentCodeKind::Bech32
        );
        let p2pkh = PaymentCode::parse(P2PKH.to_string()).unwrap();
        assert_eq!(p2pkh.encode(), P2PKH);
        assert_eq!(p2pkh.kind().unwrap(), PaymentCodeKind::Base58);
        assert_eq!(
            PaymentCode::parse(P2SH.to_string())
                .unwrap()
                .kind()
                .unwrap(),
            PaymentCodeKind::Base58
        );
    }

    #[test]
    fn base58_case_is_significant() {
        let flipped = P2PKH
            .chars()
            .map(|c| {
                if c.is_ascii_uppercase() {
                    c.to_ascii_lowercase()
                } else {
                    c.to_ascii_uppercase()
                }
            })
            .collect::<String>();
        assert!(PaymentCode::parse(flipped).is_err());
    }

    #[test]
    fn tb_matches_test_networks_but_not_regtest() {
        let address = PaymentCode::parse(TB_P2WPKH.to_string()).unwrap();
        assert!(address.is_valid_for_network(Network::Testnet3));
        assert!(address.is_valid_for_network(Network::Testnet4));
        assert!(address.is_valid_for_network(Network::Signet));
        assert!(!address.is_valid_for_network(Network::Regtest));
        assert!(!address.is_valid_for_network(Network::Mainnet));
    }

    #[test]
    fn parse_canonicalizes_uppercase_taproot() {
        let address = PaymentCode::parse(P2TR.to_uppercase()).unwrap();
        assert_eq!(address.encode(), P2TR);
        assert_eq!(address.kind().unwrap(), PaymentCodeKind::Bech32);
        assert!(address.silent_payment_code().is_none());
        assert!(address.is_valid_for_network(Network::Mainnet));
        assert!(!address.is_valid_for_network(Network::Testnet3));
        assert!(!address.is_valid_for_network(Network::Signet));
        assert!(!address.is_valid_for_network(Network::Regtest));
    }

    #[test]
    fn rejects_op_return_and_garbage() {
        assert!(PaymentCode::parse("deadbeef".to_string()).is_err());
        assert!(PaymentCode::parse("not-an-address".to_string()).is_err());
    }
}
