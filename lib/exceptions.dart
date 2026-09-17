import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/extensions/string_display.dart';

class InvalidAddressException implements Exception {}

class InvalidNetworkException implements Exception {}

class UninitializedExchangeRateException implements Exception {}

class AmbiguousPaymentUriException implements Exception {}

/// Base class for failures to obtain a usable answer for a BIP-353 name.
sealed class Bip353ResolveException implements Exception {
  final String message;
  final Object? cause;

  const Bip353ResolveException(this.message, {this.cause});

  @override
  String toString() => cause == null ? message : '$message ($cause)';
}

/// The DoH request failed: network error, non-200 status, malformed JSON.
class Bip353TransportException extends Bip353ResolveException {
  const Bip353TransportException(super.message, {super.cause});
}

/// The resolver answered with an error status (SERVFAIL, REFUSED, ...).
class Bip353DnsStatusException extends Bip353ResolveException {
  final int status;

  const Bip353DnsStatusException(super.message,
      {required this.status, super.cause});
}

/// A record exists but cannot be interpreted as a BIP-353 payment URI.
class Bip353InvalidRecordException extends Bip353ResolveException {
  const Bip353InvalidRecordException(super.message, {super.cause});
}

/// No TXT record at the name claims to be a BIP-353 payment instruction
/// (NXDOMAIN, NODATA, or only non-`bitcoin:` TXT records).
class Bip353AddressNotRegisteredException extends Bip353ResolveException {
  final Bip353Address address;

  Bip353AddressNotRegisteredException(this.address)
      : super('No payment code registered with $address, '
            'reach for the recipient to confirm their new address.');
}

/// The record exists but resolves to a different reusable payment code.
class Bip353PaymentCodeMismatchException extends Bip353ResolveException {
  final Bip353Address address;
  final String expected;

  /// The payment code found in DNS, or null if the record has none.
  final String? resolved;

  Bip353PaymentCodeMismatchException({
    required this.address,
    required this.expected,
    required this.resolved,
  }) : super('Payment code found with $address doesn\'t match '
            'what\'s recorded in your contacts.');
}

/// The name already resolves to a payment code, so it can't be registered.
class Bip353AddressAlreadyUsed extends Bip353ResolveException {
  final Bip353Address address;
  final String resolved;

  Bip353AddressAlreadyUsed({required this.address, required this.resolved})
      : super('$address is already used for payment code '
            '${resolved.truncated(prefix: 3, suffix: 4)}.');
}
