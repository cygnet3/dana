import 'dart:math';

import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:flutter_test/flutter_test.dart';

BigInt fullSatoshis = BigInt.from(pow(10, bitcoinUnits));

void main() {
  group('AmountExtension.parseUserInput', () {
    test('parses integer strings as satoshis', () {
      final amount = AmountExtension.parseUserInput('1000');

      expect(amount.field0, BigInt.from(1000));
    });

    test('trims whitespace before parsing', () {
      final amount = AmountExtension.parseUserInput('  546  ');

      expect(amount.field0, BigInt.from(546));
    });

    test('parses large integer strings as satoshis', () {
      final amount = AmountExtension.parseUserInput('9223372036854775808');

      expect(amount.field0, BigInt.parse('9223372036854775808'));
    });

    test('parses decimal strings as BTC', () {
      final amount = AmountExtension.parseUserInput('1.5');

      expect(amount.field0, BigInt.from(150000000));
    });

    test('parses BTC strings with trailing fractional zeros', () {
      final amount = AmountExtension.parseUserInput('1.0');

      expect(amount.field0, fullSatoshis);
    });

    test('parses the smallest BTC unit as one satoshi', () {
      final amount = AmountExtension.parseUserInput('0.00000001');

      expect(amount.field0, BigInt.one);
    });

    test('throws when input is empty', () {
      expect(
        () => AmountExtension.parseUserInput(''),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when integer amount is zero', () {
      expect(
        () => AmountExtension.parseUserInput('0'),
        throwsA(
          predicate<FormatException>(
            (e) => e.message == 'Amount must be positive',
          ),
        ),
      );
    });

    test('throws when BTC amount is zero', () {
      expect(
        () => AmountExtension.parseUserInput('0.0'),
        throwsA(
          predicate<FormatException>(
            (e) => e.message == 'Amount must be positive',
          ),
        ),
      );
    });

    test('throws when sats amount is negative', () {
      expect(
        () => AmountExtension.parseUserInput('-1000'),
        throwsA(
          predicate<FormatException>(
            (e) => e.message == 'Amount must be positive',
          ),
        ),
      );
    });

    test('throws when BTC amount is negative', () {
      expect(
        () => AmountExtension.parseUserInput('-1.1234'),
        throwsA(
          predicate<FormatException>(
            (e) => e.message == 'Amount must be positive',
          ),
        ),
      );
    });
    test('throws when BTC has too many decimal places', () {
      expect(
        () => AmountExtension.parseUserInput('1.123456789'),
        throwsA(
          predicate<FormatException>(
            (e) => e.message == 'BTC amount has too many decimal places',
          ),
        ),
      );
    });

    test('throws when input is not a valid amount', () {
      expect(
        () => AmountExtension.parseUserInput('not-an-amount'),
        throwsA(isA<FormatException>()),
      );
    });

    group('en_US locale formatting', () {
      test('parses grouped integer strings as satoshis', () {
        final amount = AmountExtension.parseUserInput('1,000');

        expect(amount.field0, BigInt.from(1000));
      });

      test('parses large grouped integer strings as satoshis', () {
        final amount = AmountExtension.parseUserInput('21,000,000');

        expect(amount.field0, BigInt.from(21000000));
      });

      test('parses grouped decimal strings as BTC', () {
        final amount = AmountExtension.parseUserInput('1,234.5');

        expect(amount.field0, BigInt.from(1234.5 * pow(10, bitcoinUnits)));
      });
    });

    group('non-en_US formatting', () {
      test('rejects French-style comma decimals by default', () {
        expect(
          () => AmountExtension.parseUserInput('1,5'),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects French-style spaced thousands by default', () {
        expect(
          () => AmountExtension.parseUserInput('1 000'),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
