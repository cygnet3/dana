use anyhow::Result;
use flutter_rust_bridge::frb;
use spdk_wallet::silentpayments::Network as SpNetwork;
use spdk_wallet::silentpayments::SilentPaymentCode as SpSilentPaymentCode;

use crate::api::structs::{network::Network, recipient::PaymentCode};

/// Validated BIP352 silent payment code.
///
/// Opaque to Dart: the inner value holds secp256k1 public keys, which
/// flutter_rust_bridge cannot mirror. Construct it with [`SilentPaymentCode::parse`]
/// and read the bech32m text with [`SilentPaymentCode::encode`].
///
/// `tsp` is shared by testnet3, testnet4, and signet; [`SilentPaymentCode::network`]
/// maps that HRP to [`Network::Testnet3`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[frb(opaque)]
pub struct SilentPaymentCode(SpSilentPaymentCode);

impl SilentPaymentCode {
    /// Parse a `sp1`, `tsp1`, or `sprt1` code.
    ///
    /// All-uppercase input is accepted and stored in canonical lowercase.
    #[frb(sync)]
    pub fn parse(code: String) -> Result<Self> {
        Self::parse_as_str(code.as_str())
    }

    pub(crate) fn parse_as_str(code: &str) -> Result<Self> {
        Ok(Self(SpSilentPaymentCode::try_from(code)?))
    }

    /// Canonical bech32m encoding.
    #[frb(sync)]
    pub fn encode(&self) -> String {
        self.0.to_string()
    }

    #[frb(sync)]
    pub fn version(&self) -> u8 {
        self.0.version().into()
    }

    /// Compressed scan pubkey (`B_scan`), 33 bytes.
    #[frb(sync)]
    pub fn scan_key(&self) -> Vec<u8> {
        self.0.scan_key().serialize().to_vec()
    }

    /// Compressed spend pubkey (`B_m`), 33 bytes.
    ///
    /// This is the unlabeled spend key, or a labeled one (`B_spend + m·G`).
    #[frb(sync)]
    pub fn m_pubkey(&self) -> Vec<u8> {
        self.0.m_pubkey().serialize().to_vec()
    }

    #[frb(sync)]
    pub fn network(&self) -> Network {
        match self.0.network() {
            SpNetwork::Mainnet => Network::Mainnet,
            SpNetwork::Testnet => Network::Testnet3,
            SpNetwork::Regtest => Network::Regtest,
        }
    }

    #[frb(sync)]
    pub fn is_valid_for_network(&self, network: Network) -> bool {
        match (self.0.network(), &network) {
            (SpNetwork::Mainnet, Network::Mainnet)
            | (SpNetwork::Testnet, Network::Testnet3)
            | (SpNetwork::Testnet, Network::Testnet4)
            | (SpNetwork::Testnet, Network::Signet)
            | (SpNetwork::Regtest, Network::Regtest) => true,
            _ => false,
        }
    }

    #[frb(sync)]
    pub fn to_payment_code(&self) -> PaymentCode {
        PaymentCode::from(*self)
    }

    #[frb(sync)]
    pub fn matches(&self, other: Self) -> bool {
        *self == other
    }
}

impl std::fmt::Display for SilentPaymentCode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<SpSilentPaymentCode> for SilentPaymentCode {
    fn from(value: SpSilentPaymentCode) -> Self {
        Self(value)
    }
}

impl From<SilentPaymentCode> for SpSilentPaymentCode {
    fn from(value: SilentPaymentCode) -> Self {
        value.0
    }
}

impl TryFrom<String> for SilentPaymentCode {
    type Error = anyhow::Error;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        Self::parse(value)
    }
}

impl From<SilentPaymentCode> for PaymentCode {
    fn from(value: SilentPaymentCode) -> Self {
        spdk_wallet::client::RecipientAddress::SpCode(value.0).into()
    }
}

impl TryFrom<PaymentCode> for SilentPaymentCode {
    type Error = anyhow::Error;

    fn try_from(value: PaymentCode) -> Result<Self, Self::Error> {
        match spdk_wallet::client::RecipientAddress::from(value) {
            spdk_wallet::client::RecipientAddress::SpCode(code) => Ok(Self(code)),
            other => Err(anyhow::anyhow!(
                "expected silent payment code, got {}",
                String::from(other)
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use spdk_wallet::bitcoin::secp256k1::{PublicKey, Secp256k1, SecretKey};
    use spdk_wallet::silentpayments::{Network as SpNetwork, SpVersion};

    use super::*;

    const SP_ADDRESS: &str = "sp1qq2xewwk5u02gxxurdzr6r6jerelncw82rlyvw2kpggxt3pum4kp6yq62utdcljdtmxpy3vs7c940hvjuzedhhsf7h2y5lflk7zp2xhgz3vryqw4n";

    fn keys() -> (PublicKey, PublicKey) {
        let secp = Secp256k1::new();
        let scan = SecretKey::from_slice(&[0x01; 32])
            .unwrap()
            .public_key(&secp);
        let spend = SecretKey::from_slice(&[0x02; 32])
            .unwrap()
            .public_key(&secp);
        (scan, spend)
    }

    fn code_on(network: SpNetwork) -> SilentPaymentCode {
        let (scan, spend) = keys();
        SilentPaymentCode::from(SpSilentPaymentCode::new(
            SpVersion::ZERO,
            scan,
            spend,
            network,
        ))
    }

    #[test]
    fn parse_canonicalizes_uppercase_mainnet_code() {
        let code = SilentPaymentCode::parse(SP_ADDRESS.to_uppercase()).unwrap();
        assert_eq!(code.encode(), SP_ADDRESS);
        assert_eq!(code.to_string(), SP_ADDRESS);
        assert!(matches!(code.network(), Network::Mainnet));
        assert_eq!(code.version(), 0);
        assert_eq!(code.scan_key().len(), 33);
        assert_eq!(code.m_pubkey().len(), 33);
        assert!(matches!(code.scan_key()[0], 0x02 | 0x03));
        assert!(matches!(code.m_pubkey()[0], 0x02 | 0x03));
    }

    #[test]
    fn network_maps_sp_hrp_to_wallet_network() {
        assert!(matches!(
            code_on(SpNetwork::Mainnet).network(),
            Network::Mainnet
        ));
        // `tsp` cannot distinguish testnet3/4/signet; mapped to Testnet3.
        assert!(matches!(
            code_on(SpNetwork::Testnet).network(),
            Network::Testnet3
        ));
        assert!(matches!(
            code_on(SpNetwork::Regtest).network(),
            Network::Regtest
        ));
    }

    #[test]
    fn rejects_invalid_code() {
        let err = SilentPaymentCode::parse("not-a-code".to_string()).unwrap_err();
        assert!(!err.to_string().is_empty());
    }

    #[test]
    fn converts_to_payment_code_without_reparsing() {
        let code = SilentPaymentCode::parse(SP_ADDRESS.to_string()).unwrap();
        let payment = code.to_payment_code();
        assert_eq!(payment.encode(), code.encode());
        assert_eq!(payment.silent_payment_code(), Some(code));
    }

    #[test]
    fn roundtrips_through_library_type() {
        let original = {
            let (scan, spend) = keys();
            SpSilentPaymentCode::new(SpVersion::ZERO, scan, spend, SpNetwork::Testnet)
        };
        let wrapped = SilentPaymentCode::from(original);
        assert!(matches!(wrapped.network(), Network::Testnet3));
        assert_eq!(wrapped.encode(), original.to_string());

        let restored = SpSilentPaymentCode::from(wrapped);
        assert_eq!(restored, original);
        assert_eq!(restored.scan_key(), original.scan_key());
        assert_eq!(restored.m_pubkey(), original.m_pubkey());
    }
}
