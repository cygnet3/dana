import 'package:danawallet/constants.dart';

/// Whole and fractional parts of a user-entered decimal amount.
typedef DecimalParts = (String wholePart, String fractionPart);

/// Splits [input] on [decimalSeparator] into whole and fractional parts.
DecimalParts parseDecimalParts(String input) {
  final parts = input.split(decimalSeparator);
  if (parts.length == 1) {
    return (input, '');
  }
  if (parts.length != 2) {
    throw FormatException('Invalid amount: $input');
  }

  final wholePart = parts[0];
  if (wholePart.isEmpty) {
    throw const FormatException('Amount has an empty whole part');
  }

  final fractionPart = parts[1];
  if (fractionPart.isEmpty) {
    throw const FormatException('Amount has an empty fraction part');
  }
  if (fractionPart.contains(RegExp(r'\D'))) {
    throw FormatException(
        'Amount has an invalid fraction part \'$fractionPart\'');
  }

  return (wholePart, fractionPart);
}

/// Strips [groupSeparator] from [wholePart] after validating grouping rules.
String validateGroupedDigits(String wholePart) {
  final parts = wholePart.split(groupSeparator);
  if (parts.length > 1) {
    if (parts[0].isEmpty) {
      throw const FormatException(
          'Incorrectly formatted number: starting with a \'$groupSeparator\'');
    }
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
  }
  return wholePart;
}

class ParsedDecimalInput {
  final String sanitizedWholePart;
  final String fractionPart;

  const ParsedDecimalInput({
    required this.sanitizedWholePart,
    required this.fractionPart,
  });

  bool get hasDecimal => fractionPart.isNotEmpty;
}

/// Parses grouped decimal user input shared by BTC and fiat amount fields.
ParsedDecimalInput parseGroupedDecimalInput(
  String text,
  int maxFractionDigits,
) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Amount is empty');
  }

  final (wholePart, fractionPart) = parseDecimalParts(trimmed);
  final sanitizedWholePart = validateGroupedDigits(wholePart);
  if (sanitizedWholePart.contains(RegExp(r'\D'))) {
    throw FormatException('Invalid whole part \'$wholePart\'');
  }

  if (fractionPart.isNotEmpty) {
    if (maxFractionDigits == 0) {
      throw const FormatException('Decimals not supported');
    } else if (fractionPart.length > maxFractionDigits) {
      throw FormatException(
          'Too many decimal places: expected $maxFractionDigits, got ${fractionPart.length}');
    }
  }

  return ParsedDecimalInput(
    sanitizedWholePart: sanitizedWholePart,
    fractionPart: fractionPart,
  );
}
