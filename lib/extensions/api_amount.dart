import 'package:danawallet/constants.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';

extension AmountExtension on Amount {
  Amount operator +(Amount other) {
    return Amount(field0: field0 + other.field0);
  }

  Amount operator -(Amount other) {
    return Amount(field0: field0 - other.field0);
  }

  bool operator >(Amount other) {
    return field0 > other.field0;
  }

  bool operator <(Amount other) {
    return field0 < other.field0;
  }

  String displayBtc() {
    final btcPart = field0 ~/ BigInt.from(bitcoinUnits);
    final satsPart = (field0 % BigInt.from(bitcoinUnits));
    final satsStr = satsPart.toString().padLeft(8, '0');
    return '₿ $btcPart.${satsStr.substring(0, 2)} ${satsStr.substring(2, 5)} ${satsStr.substring(5, 8)}';
  }

  String displaySats() {
    return '$field0 sats';
  }

  /// Converts a [BigInt] satoshi amount to [int] for SQLite storage.
  /// Throws a [StateError] if the value exceeds the safe integer range,
  /// preventing silent data corruption on overflow.
  int toSat() {
    if (!field0.isValidInt) {
      throw StateError('Amount overflows int: $field0');
    }
    return field0.toInt();
  }

  static Amount fromDbValue(Object? value) {
    if (value == null) {
      throw StateError('Db value is null');
    }
    if (value is int) {
      return Amount(field0: BigInt.from(value.toInt()));
    } else if (value is BigInt) {
      return Amount(field0: value);
    } else {
      throw StateError('Invalid amount type: ${value.runtimeType}');
    }
  }
}
