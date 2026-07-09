import 'package:danawallet/parsing/amount_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseGroupedDecimalInput', () {
    test('parses BTC amounts with up to 8 fraction digits', () {
      final parsed = parseGroupedDecimalInput('0.00000001', 8);

      expect(parsed.sanitizedWholePart, '0');
      expect(parsed.fractionPart, '00000001');
      expect(parsed.hasDecimal, isTrue);
    });
  });
}
