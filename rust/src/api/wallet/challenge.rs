use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use spdk_wallet::bitcoin::hashes::{sha256, Hash};
use spdk_wallet::bitcoin::secp256k1::{self, Keypair, Message, SecretKey};
use std::str::FromStr;

/// All challenge messages signed by this oracle must carry this prefix. The
/// nameserver (Sosthene00/dana-nameserver issue #20) only ever accepts
/// attestations over messages beginning with it; refusing anything else keeps
/// this from turning into an arbitrary-string signing oracle on the spend key.
pub const CHALLENGE_PREFIX: &str = "dana-register:";

/// Lowercase hex of a serialized byte array.
fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
}

/// The SHA-256 digest the nameserver expects under a BIP-340 `Message`
/// (README @ fe1c49d defines this pre-hash contract).
fn challenge_digest(message: &str) -> [u8; 32] {
    sha256::Hash::hash(message.as_bytes()).to_byte_array()
}

/// Signs a nameserver challenge attestation with the spend key (BIP-340
/// schnorr).
///
/// The message is pre-hashed with SHA-256 — the *digest*, never the raw
/// preimage, is what goes into the BIP-340 `Message` (see
/// `raw_preimage_signature_does_not_verify`, which locks that contract with
/// the nameserver). Returns the 64-byte signature as lowercase hex.
///
/// The spend secret crosses the FFI boundary as hex here on purpose: this is
/// a pure signing oracle (message string in, signature string out) and needs
/// no wallet state. We deliberately do *not* reuse `ApiSpendKey` for the
/// secret: the established FRB key pattern (`ApiScanKey`/`ApiSpendKey`,
/// wallet.rs:46) is a JSON-encoded wallet handle passed by value through
/// `encode`/`decode`, which does not fit a stateless string-in/string-out
/// oracle call.
#[frb(sync)]
pub fn sign_challenge(spend_secret: &str, message: &str) -> Result<String> {
    let sk = SecretKey::from_str(spend_secret)?;
    Ok(to_hex(&sign_challenge_inner(&sk, message)?.serialize()))
}

/// Core of [`sign_challenge`], factored out so tests can assert the digest
/// path directly against raw-preimage signatures.
fn sign_challenge_inner(sk: &SecretKey, message: &str) -> Result<secp256k1::schnorr::Signature> {
    if !message.starts_with(CHALLENGE_PREFIX) {
        return Err(anyhow!("challenge message must start with '{CHALLENGE_PREFIX}'"));
    }

    let secp = secp256k1::Secp256k1::signing_only();
    let keypair = Keypair::from_secret_key(&secp, sk);
    let msg = Message::from_digest(challenge_digest(message));
    // Deterministic BIP-340 auxiliary random data: sha256(secret). No caller
    // nonce to misuse, and the nameserver only verifies the final signature.
    let aux = sha256::Hash::hash(&sk.secret_bytes()).to_byte_array();
    Ok(secp.sign_schnorr_with_aux_rand(&msg, &keypair, &aux))
}

#[cfg(test)]
mod tests {
    use super::*;
    use spdk_wallet::bitcoin::secp256k1::schnorr::Signature;
    use spdk_wallet::bitcoin::secp256k1::{Secp256k1, XOnlyPublicKey};

    /// Fixed spend secret (sk = 1) so the produced signature is a
    /// reproducible vector.
    const SK_HEX: &str = "0000000000000000000000000000000000000000000000000000000000000001";
    const MSG: &str = "dana-register:9f2c7a4e1b8d3f6a05c2e8b47d1a9f3c6e0b2a8d4f17c3e9a2b5d8f0c1e4a7b9";

    /// The (x-only, even-parity-normalised) verification key belonging to
    /// `sk`, via the 0.29 `SecretKey::x_only_public_key` path.
    fn xonly_even(sk: &SecretKey) -> XOnlyPublicKey {
        let secp = Secp256k1::signing_only();
        sk.x_only_public_key(&secp).0
    }

    fn hex_val(c: u8) -> Option<u8> {
        match c {
            b'0'..=b'9' => Some(c - b'0'),
            b'a'..=b'f' => Some(c - b'a' + 10),
            _ => None,
        }
    }

    fn from_hex(s: &str) -> Option<Vec<u8>> {
        if !s.len().is_multiple_of(2) {
            return None;
        }
        s.as_bytes()
            .chunks(2)
            .map(|c| Some(hex_val(c[0])? * 16 + hex_val(c[1])?))
            .collect::<Option<Vec<u8>>>()
    }

    fn verify(sig: &Signature, msg: &Message, sk: &SecretKey) -> Result<(), secp256k1::Error> {
        let secp = Secp256k1::verification_only();
        secp.verify_schnorr(sig, msg, &xonly_even(sk))
    }

    #[test]
    fn fixed_vectors_sign_and_verify() {
        let sig_hex = sign_challenge(SK_HEX, MSG).unwrap();
        // 64-byte signature => 128 lowercase-hex chars.
        assert_eq!(sig_hex.len(), 128);
        assert!(sig_hex
            .chars()
            .all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c)));
        let bytes = from_hex(&sig_hex).expect("output is even-length hex");
        assert_eq!(bytes.len(), 64);

        let sig = Signature::from_slice(&bytes).unwrap();
        // Verification goes through the SAME sha256-digest path the wallet
        // signed: Message::from_digest(sha256(message)), rebuilt here
        // independently of the signing helper.
        let digest = sha256::Hash::hash(MSG.as_bytes()).to_byte_array();
        let msg = Message::from_digest(digest);
        let sk = SecretKey::from_str(SK_HEX).unwrap();
        verify(&sig, &msg, &sk).expect("fixed-vector signature must verify");
    }

    #[test]
    fn raw_preimage_signature_does_not_verify() {
        // Locks the sha256 pre-hash contract with the nameserver (README @
        // fe1c49d): a signature made over the RAW message bytes (no sha256)
        // must fail verification against the digest the wallet actually signs.
        // A BIP-340 `Message` is exactly 32 bytes, so "raw" here is the
        // first 32 bytes of the preimage taken verbatim, un-hashed.
        let sk = SecretKey::from_str(SK_HEX).unwrap();
        let secp = Secp256k1::signing_only();
        let keypair = Keypair::from_secret_key(&secp, &sk);
        let raw = Message::from_digest_slice(&MSG.as_bytes()[..32]).unwrap();
        let raw_sig = secp.sign_schnorr_no_aux_rand(&raw, &keypair);

        let digest_msg = Message::from_digest(challenge_digest(MSG));
        assert!(
            verify(&raw_sig, &digest_msg, &sk).is_err(),
            "signature over the raw preimage must NOT verify against the sha256 digest"
        );

        // ... and the wallet-produced signature *does* verify against the
        // digest — so the mismatch above is about the pre-hash, not a key bug.
        let wallet_sig = sign_challenge_inner(&sk, MSG).unwrap();
        verify(&wallet_sig, &digest_msg, &sk)
            .expect("wallet signature verifies against the digest path");
    }

    #[test]
    fn malformed_secret_hex_is_rejected() {
        // Err, never panic.
        assert!(sign_challenge("not-hex", MSG).is_err());
        assert!(sign_challenge("", MSG).is_err());
        assert!(sign_challenge("00", MSG).is_err()); // wrong length
        assert!(sign_challenge("0", MSG).is_err()); // odd length
        let over_long = "ff".repeat(64);
        assert!(sign_challenge(&over_long, MSG).is_err()); // > 32 bytes
    }

    #[test]
    fn missing_prefix_is_rejected() {
        // No arbitrary-string signing oracle on the spend key.
        assert!(sign_challenge(SK_HEX, "please send coins").is_err());
        assert!(sign_challenge(SK_HEX, "Dana-register:case-mismatch").is_err());
        assert!(sign_challenge(SK_HEX, "").is_err());
        // The exact prefix (even with an empty payload) is accepted.
        assert!(sign_challenge(SK_HEX, "dana-register:").is_ok());
    }

    #[test]
    fn output_is_always_canonical_64_bytes() {
        // BIP-340 signatures are fixed-size; anything this fn emits must
        // round-trip through `Signature::from_slice` (which only accepts the
        // canonical 64-byte serialization) and verify. A non-canonical
        // 64-byte output is therefore never produced.
        let s1 = "01".repeat(63);
        let s2 = "6b".repeat(64);
        for secret in [SK_HEX, &s1[..], &s2[..]] {
            if let Ok(sig_hex) = sign_challenge(secret, MSG) {
                let bytes = from_hex(&sig_hex).expect("output is even-length lowercase hex");
                assert_eq!(bytes.len(), 64);
                let sig = Signature::from_slice(&bytes)
                    .expect("output must be a canonical 64-byte schnorr signature");
                let sk = SecretKey::from_str(secret).unwrap();
                let msg = Message::from_digest(challenge_digest(MSG));
                verify(&sig, &msg, &sk).unwrap();
            }
        }
    }
}
