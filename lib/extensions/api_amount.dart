import 'dart:math';

import 'package:danawallet/constants.dart';
import 'package:danawallet/data/enums/amount_display_unit.dart';
import 'package:danawallet/parsing/amount_input.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';

BigInt _stringToDecimals(
    String wholePart, String fractionPart, int maxFractionDigits) {
  if (maxFractionDigits < 0) {
    throw Exception('maxFractionDigits can\'t be negative');
  }
  final whole = BigInt.parse(wholePart);

  BigInt decimals;
  if (maxFractionDigits > 0) {
    final fractions =
        BigInt.parse(fractionPart.padRight(maxFractionDigits, '0'));
    decimals = whole * BigInt.from(pow(10, maxFractionDigits)) + fractions;
  } else {
    decimals = whole;
  }
  if (decimals <= BigInt.zero) {
    throw const FormatException('Amount must be positive');
  }
  return decimals;
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

  /// Parses user-entered fiat amounts into minor units (e.g. cents).
  /// Whole numbers and decimals are both major units (e.g. dollars).
  static BigInt parseFiatInput(String text, int currencyMaxDecimals) {
    final parsed = parseGroupedDecimalInput(
      text,
      currencyMaxDecimals,
    );

    return _stringToDecimals(
      parsed.sanitizedWholePart,
      parsed.fractionPart,
      currencyMaxDecimals,
    );
  }

  /// Parses user-entered BTC/sats amounts into satoshis.
  /// Integer strings are satoshis; decimals are BTC.
  static Amount parseBtcInput(String text) {
    final parsed = parseGroupedDecimalInput(
      text,
      bitcoinUnits,
    );

    if (!parsed.hasDecimal) {
      final satsAmount = BigInt.parse(parsed.sanitizedWholePart);
      if (satsAmount <= BigInt.zero) {
        throw const FormatException('Amount must be positive');
      }
      return Amount(field0: satsAmount);
    } else {
      return Amount(
          field0: _stringToDecimals(
              parsed.sanitizedWholePart, parsed.fractionPart, bitcoinUnits));
    }
  }

  String _displayBtc() {
    final btcPart = field0 ~/ BigInt.from(pow(10, bitcoinUnits));
    final satsPart = (field0 % BigInt.from(pow(10, bitcoinUnits)));
    final satsStr = satsPart.toString().padLeft(bitcoinUnits, '0');
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
