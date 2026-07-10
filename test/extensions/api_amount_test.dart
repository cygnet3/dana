import 'dart:math';

import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:flutter_test/flutter_test.dart';

BigInt fullSatoshis = BigInt.from(pow(10, bitcoinUnits));

void main() {
  group('AmountExtension.parseBtcInput', () {
    test('parses integer strings as satoshis', () {
      final amount = AmountExtension.parseBtcInput('1000');

      expect(amount.field0, BigInt.from(1000));
    });

    test('trims whitespace before parsing', () {
      final amount = AmountExtension.parseBtcInput('  546  ');

      expect(amount.field0, BigInt.from(546));
    });

    test('parses large integer strings as satoshis', () {
      final amount = AmountExtension.parseBtcInput('9223372036854775808');

      expect(amount.field0, BigInt.parse('9223372036854775808'));
    });

    test('parses decimal strings as BTC', () {
      final amount = AmountExtension.parseBtcInput('1.5');

      expect(amount.field0, BigInt.from(150000000));
    });

    test('parses BTC strings with trailing fractional zeros', () {
      final amount = AmountExtension.parseBtcInput('1.0');

      expect(amount.field0, fullSatoshis);
    });

    test('parses the smallest BTC unit as one satoshi', () {
      final amount = AmountExtension.parseBtcInput('0.00000001');

      expect(amount.field0, BigInt.one);
    });

    test('throws when input is empty', () {
      expect(
        () => AmountExtension.parseBtcInput(''),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when integer amount is zero', () {
      expect(
        () => AmountExtension.parseBtcInput('0'),
        throwsA(
          predicate<FormatException>(
            (e) => e.message == 'Amount must be positive',
          ),
        ),
      );
    });

    test('throws when BTC amount is zero', () {
      expect(
        () => AmountExtension.parseBtcInput('0.0'),
        throwsA(
          predicate<FormatException>(
            (e) => e.message == 'Amount must be positive',
          ),
        ),
      );
    });

    test('throws when sats amount is negative', () {
      expect(
        () => AmountExtension.parseBtcInput('-1000'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when BTC amount is negative', () {
      expect(
        () => AmountExtension.parseBtcInput('-1.1234'),
        throwsA(isA<FormatException>()),
      );
    });
    test('throws when BTC has too many decimal places', () {
      expect(
        () => AmountExtension.parseBtcInput('1.123456789'),
        throwsA(
          predicate<FormatException>(
            (e) =>
                e.message == 'Too many decimal places: expected 8, got 9',
          ),
        ),
      );
    });

    test('throws when input is not a valid amount', () {
      expect(
        () => AmountExtension.parseBtcInput('not-an-amount'),
        throwsA(isA<FormatException>()),
      );
    });

    group('en_US locale formatting', () {
      test('parses grouped integer strings as satoshis', () {
        final amount = AmountExtension.parseBtcInput('1,000');

        expect(amount.field0, BigInt.from(1000));
      });

      test('parses large grouped integer strings as satoshis', () {
        final amount = AmountExtension.parseBtcInput('21,000,000');

        expect(amount.field0, BigInt.from(21000000));
      });

      test('parses grouped decimal strings as BTC', () {
        final amount = AmountExtension.parseBtcInput('1,234.5');

        expect(amount.field0, BigInt.from(1234.5 * pow(10, bitcoinUnits)));
      });
    });

    group('non-en_US formatting', () {
      test('rejects French-style comma decimals by default', () {
        expect(
          () => AmountExtension.parseBtcInput('1,5'),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects French-style spaced thousands by default', () {
        expect(
          () => AmountExtension.parseBtcInput('1 000'),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });

  group('AmountExtension.parseFiatInput', () {
    test('parses integer strings as major units into minor units', () {
      final amount = AmountExtension.parseFiatInput('100', 2);

      expect(amount, BigInt.from(10000));
    });

    test('parses decimal strings as major units into minor units', () {
      final amount = AmountExtension.parseFiatInput('50.5', 2);

      expect(amount, BigInt.from(5050));
    });

    test('parses grouped decimal strings', () {
      final amount = AmountExtension.parseFiatInput('1,234.56', 2);

      expect(amount, BigInt.from(123456));
    });

    test('parses whole amounts for zero-decimal currencies', () {
      final amount = AmountExtension.parseFiatInput('1000', 0);

      expect(amount, BigInt.from(1000));
    });

    test('throws when integer amount is zero', () {
      expect(
        () => AmountExtension.parseFiatInput('0', 2),
        throwsA(
          predicate<FormatException>(
            (e) => e.message == 'Amount must be positive',
          ),
        ),
      );
    });
  });
}
