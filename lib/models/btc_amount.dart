/// Dart-side alias for satoshi amounts (was `ApiAmount` on the Rust side).
typedef BtcAmount = BigInt;

/// Convenience constructor in app code (satoshis).
BtcAmount btcAmountFromSats(BigInt sats) => sats;
