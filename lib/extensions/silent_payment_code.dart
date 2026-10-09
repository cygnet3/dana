import 'package:danawallet/generated/rust/api/structs/silent_payment_code.dart';

/// Parse [raw] as a silent payment code.
///
/// All-uppercase input is accepted. The returned value's [SilentPaymentCode.encode]
/// is the canonical lowercase bech32m text. Returns null for legacy addresses,
/// empty text, and mixed-case codes.
SilentPaymentCode? tryParseSilentPaymentCode(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    return SilentPaymentCode.parse(code: trimmed);
  } catch (_) {
    return null;
  }
}
