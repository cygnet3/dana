use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use spdk_wallet::bip321::Bip321Uri as SpdkBip321Uri;
use spdk_wallet::client::SpUriExtension;
use spdk_wallet::silentpayments::SilentPaymentCode;

use crate::api::structs::amount::Amount;
use crate::api::structs::bip321_uri::Bip321Uri;

/// Parses a BIP21 or BIP321 payment URI (e.g. from a scanned QR code).
///
/// Returns URI fields in a Dart-friendly shape that closely mirrors `Bip321Uri`:
/// `sp`, `tsp`, `bc`, `tb`, legacy body `address`, and optional `amount`.
/// `sp` / `tsp` are parsed and re-encoded so callers always get lowercase addresses.
/// Invalid `sp` / `tsp` entries are skipped rather than failing the whole URI.
#[frb(sync)]
pub fn parse_payment_uri(uri: String) -> Result<Bip321Uri> {
    let parsed: SpdkBip321Uri<SpUriExtension> = uri
        .as_str()
        .parse()
        .map_err(|e| anyhow!("Invalid BIP21 URI: {}", e))?;

    Ok(Bip321Uri {
        sp: parsed
            .sp()
            .iter()
            .filter_map(|field| {
                let sp_address = SilentPaymentCode::try_from(field.inner().as_str());
                match sp_address {
                    Ok(address) => Some(address.to_string()),
                    Err(_) => None,
                }
            })
            .collect(),
        tsp: parsed
            .extensions()
            .tsp()
            .iter()
            .filter_map(|field| {
                let sp_address = SilentPaymentCode::try_from(field.inner().as_str());
                match sp_address {
                    Ok(address) => Some(address.to_string()),
                    Err(_) => None,
                }
            })
            .collect(),
        bc: parsed
            .bc()
            .iter()
            .map(|field| field.inner().to_string())
            .collect(),
        tb: parsed
            .tb()
            .iter()
            .map(|field| field.inner().to_string())
            .collect(),
        address: parsed.address().map(|address| address.to_string()),
        amount: parsed.amount().copied().map(Amount::from),
    })
}

#[cfg(test)]
mod tests {
    use spdk_wallet::bitcoin::secp256k1::{Secp256k1, SecretKey};
    use spdk_wallet::silentpayments::{Network as SpNetwork, SpVersion};

    use super::*;

    const SP_ADDRESS: &str = "sp1qq2xewwk5u02gxxurdzr6r6jerelncw82rlyvw2kpggxt3pum4kp6yq62utdcljdtmxpy3vs7c940hvjuzedhhsf7h2y5lflk7zp2xhgz3vryqw4n";

    fn testnet_sp_address() -> SilentPaymentCode {
        let secp = Secp256k1::new();
        let scan = SecretKey::from_slice(&[0x01; 32])
            .unwrap()
            .public_key(&secp);
        let spend = SecretKey::from_slice(&[0x02; 32])
            .unwrap()
            .public_key(&secp);
        SilentPaymentCode::new(SpVersion::ZERO, scan, spend, SpNetwork::Testnet)
    }

    #[test]
    fn maps_sp_with_amount() {
        let uri = format!("bitcoin:?sp={SP_ADDRESS}&amount=0.001");
        let result = parse_payment_uri(uri).unwrap();
        assert_eq!(result.sp, vec![SP_ADDRESS.to_string()]);
        assert!(result.tsp.is_empty());
        assert!(result.bc.is_empty());
        assert!(result.tb.is_empty());
        assert_eq!(result.address, None);
        assert_eq!(result.amount, Some(Amount(100_000)));
    }

    #[test]
    fn maps_tsp_with_amount() {
        let tsp = testnet_sp_address().to_string();
        let uri = format!("bitcoin:?tsp={tsp}&amount=0.001");
        let result = parse_payment_uri(uri).unwrap();
        assert_eq!(result.tsp, vec![tsp]);
        assert!(result.sp.is_empty());
        assert!(result.bc.is_empty());
        assert!(result.tb.is_empty());
        assert_eq!(result.address, None);
        assert_eq!(result.amount, Some(Amount(100_000)));
    }

    #[test]
    fn maps_bc_tb_and_legacy_address_without_network_filtering() {
        let uri = "bitcoin:1andreas3batLhQa2FawWjeyjCqyBzypd?bc=bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq&tb=tb1qghfhmd4zh7ncpmxl3qzhmq566jk8ckq4gafnmg";
        let result = parse_payment_uri(uri.to_string()).unwrap();
        assert_eq!(
            result.bc,
            vec!["bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq".to_string()]
        );
        assert_eq!(
            result.tb,
            vec!["tb1qghfhmd4zh7ncpmxl3qzhmq566jk8ckq4gafnmg".to_string()]
        );
        assert_eq!(
            result.address.as_deref(),
            Some("1andreas3batLhQa2FawWjeyjCqyBzypd")
        );
    }

    #[test]
    fn maps_duplicate_slots_as_multiple_entries() {
        let uri = "bitcoin:?bc=bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq&bc=bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq";
        let result = parse_payment_uri(uri.to_string()).unwrap();
        assert_eq!(
            result.bc,
            vec![
                "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq".to_string(),
                "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq".to_string()
            ]
        );
        assert!(result.sp.is_empty());
        assert!(result.tsp.is_empty());
        assert!(result.tb.is_empty());
        assert_eq!(result.address, None);
    }

    #[test]
    fn maps_legacy_address_only() {
        let uri = "bitcoin:1andreas3batLhQa2FawWjeyjCqyBzypd";
        let result = parse_payment_uri(uri.to_string()).unwrap();
        assert!(result.sp.is_empty());
        assert!(result.tsp.is_empty());
        assert!(result.bc.is_empty());
        assert!(result.tb.is_empty());
        assert_eq!(
            result.address.as_deref(),
            Some("1andreas3batLhQa2FawWjeyjCqyBzypd")
        );
        assert_eq!(result.amount, None);
    }

    #[test]
    fn uppercase_sp_is_canonicalized_to_lowercase() {
        let uri = format!("bitcoin:?sp={}", SP_ADDRESS.to_uppercase());
        let result = parse_payment_uri(uri).unwrap();
        assert_eq!(result.sp, vec![SP_ADDRESS.to_string()]);
    }

    #[test]
    fn mixed_case_sp_is_skipped() {
        // All-lower HRP with one uppercase data character → BIP-173 mixed case.
        let mixed = format!("sp1Q{}", &SP_ADDRESS["sp1q".len()..]);
        let uri = format!("bitcoin:?sp={mixed}");
        let result = parse_payment_uri(uri).unwrap();
        assert!(result.sp.is_empty());
    }

    #[test]
    fn invalid_sp_does_not_drop_valid_tsp() {
        let tsp = testnet_sp_address().to_string();
        let mixed = format!("sp1Q{}", &SP_ADDRESS["sp1q".len()..]);
        let uri = format!("bitcoin:?sp={mixed}&tsp={tsp}");
        let result = parse_payment_uri(uri).unwrap();
        assert!(result.sp.is_empty());
        assert_eq!(result.tsp, vec![tsp]);
    }

    #[test]
    fn amount_without_destination_is_rejected() {
        let uri = "bitcoin:?amount=0.001";
        let result = parse_payment_uri(uri.to_string());
        assert!(result.is_err());
        let err = result.unwrap_err().to_string();
        assert!(err.contains("no payment destination"), "unexpected: {err}");
    }

    #[test]
    fn invalid_legacy_checksum_is_rejected() {
        let uri = "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W";
        let result = parse_payment_uri(uri.to_string());
        assert!(result.is_err());
        let err = result.unwrap_err().to_string();
        assert!(err.contains("Invalid BIP21 URI"), "unexpected: {err}");
    }

    #[test]
    fn testnet_address_in_body_is_rejected() {
        let uri = "bitcoin:tb1qghfhmd4zh7ncpmxl3qzhmq566jk8ckq4gafnmg";
        let result = parse_payment_uri(uri.to_string());
        assert!(result.is_err());
        let err = result.unwrap_err().to_string();
        assert!(err.contains("Invalid BIP21 URI"), "unexpected: {err}");
    }
}
