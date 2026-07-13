import 'package:danawallet/constants.dart';
import 'package:danawallet/data/enums/amount_display_unit.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';

BigInt _btcStringToSats(String wholePart, String fractionPart) {
  if (fractionPart.length > 8) {
    throw const FormatException('BTC amount has too many decimal places');
  }

  final whole = BigInt.parse(wholePart);
  final fractionSats = BigInt.parse(fractionPart.padRight(8, '0'));

  final sats = whole * BigInt.from(bitcoinUnits) + fractionSats;
  if (sats <= BigInt.zero) {
    throw const FormatException('Amount must be positive');
  }
  return sats;
}

(String, String) _parseDecimal(String input) {
  final parts = input.split(decimalSeparator);
  if (parts.length == 1) {
    return (input, ''); // We return only the whole part
  }
  if (parts.length != 2) {
    // Having more than one decimal separator is invalid input
    throw FormatException('Invalid BTC amount: $input');
  }

  final wholePart = parts[0];
  if (wholePart.isEmpty) {
    throw const FormatException('BTC amount has an empty whole part');
  } else if (wholePart.contains(RegExp(r'\D'))) {
    throw FormatException(
        'BTC amount has an invalid whole part \'$wholePart\'');
  }
  final fractionPart = parts[1];
  if (fractionPart.length > 8) {
    throw const FormatException('BTC amount has too many decimal places');
  } else if (fractionPart.isEmpty) {
    throw const FormatException('BTC amount with empty fraction part');
  }
  return (wholePart, fractionPart);
}

String _validateGroupsDigits(String wholePart) {
  final parts = wholePart.split(groupSeparator);
  if (parts.length > 1) {
    // We protect against trailing comma at the beginning
    if (parts[0].isEmpty) {
      throw const FormatException(
          'Incorrectly formatted number: starting with a \'$groupSeparator\'');
    }
    // Other than the first part, each part must be 3 digits
    for (var i = 1; i < parts.length; i++) {
      final part = parts[i];
      if (part.length != 3) {
        throw const FormatException(
            'Group separator must be followed by exactly 3 digits');
      } else if (part.contains(RegExp(r'\D'))) {
        throw FormatException('Invalid character in grouped number $part');
      }
    }

    return parts.join();
  } else {
    // There's no separator, just return the input as is
    return wholePart;
  }
}

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

  /// Parses user-entered spend amounts. Integer strings are interpreted as
  /// satoshis; non-integer strings are parsed as BTC.
  static Amount parseUserInput(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Amount is empty');
    }

    final (wholePart, fractionPart) = _parseDecimal(trimmed);
    final sanitizedWholePart = _validateGroupsDigits(wholePart);

    final hasDecimal = fractionPart.isNotEmpty;

    if (!hasDecimal) {
      final satsAmount = BigInt.parse(sanitizedWholePart);
      if (satsAmount <= BigInt.zero) {
        throw const FormatException('Amount must be positive');
      }
      return Amount(field0: satsAmount);
    } else {
      return Amount(field0: _btcStringToSats(sanitizedWholePart, fractionPart));
    }
  }

  String _displayBtc() {
    final btcPart = field0 ~/ BigInt.from(bitcoinUnits);
    final satsPart = (field0 % BigInt.from(bitcoinUnits));
    final satsStr = satsPart.toString().padLeft(8, '0');
    return '$btcSymbol $btcPart.${satsStr.substring(0, 2)} ${satsStr.substring(2, 5)} ${satsStr.substring(5, 8)}';
  }

  String _displaySats() {
    return '$satSymbol $field0';
  }

  String display(AmountDisplayUnit bitcoinUnit) {
    switch (bitcoinUnit) {
      case AmountDisplayUnit.btc:
        return _displayBtc();
      case AmountDisplayUnit.sats:
        return _displaySats();
    }
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
