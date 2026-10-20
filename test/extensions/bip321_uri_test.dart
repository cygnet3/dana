import 'package:danawallet/exceptions.dart';
import 'package:danawallet/extensions/bip321_uri.dart';
import 'package:danawallet/generated/rust/api/structs/bip321_uri.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bip321Uri uri({
    List<String> sp = const [],
    List<String> tsp = const [],
  }) =>
      Bip321Uri(sp: sp, tsp: tsp, bc: const [], tb: const []);

  group('Bip321Uri.reusablePaymentCodeForNetwork', () {
    // Success-path coverage (parse + encode) lives in Rust bip321 tests;
    // these Dart tests stay FFI-free and only cover selection / ambiguity.

    test('returns null when the record has no reusable payment code', () {
      expect(
        uri().reusablePaymentCodeForNetwork(Network.mainnet),
        isNull,
      );
    });

    test('ignores sp on test networks', () {
      expect(
        uri(sp: const ['sp1qours']).reusablePaymentCodeForNetwork(
          Network.signet,
        ),
        isNull,
      );
    });

    test('throws AmbiguousPaymentUriException when multiple sp codes exist',
        () {
      expect(
        () => uri(sp: const ['sp1qa', 'sp1qb'])
            .reusablePaymentCodeForNetwork(Network.mainnet),
        throwsA(isA<AmbiguousPaymentUriException>()),
      );
    });

    test('throws AmbiguousPaymentUriException when multiple tsp codes exist',
        () {
      expect(
        () => uri(tsp: const ['tsp1qa', 'tsp1qb'])
            .reusablePaymentCodeForNetwork(Network.testnet4),
        throwsA(isA<AmbiguousPaymentUriException>()),
      );
    });
  });
}
