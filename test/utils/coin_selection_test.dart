import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/input_selection.dart';
import 'package:danawallet/utils/coin_selection.dart';
import 'package:flutter_test/flutter_test.dart';

InputSelection selection({
  required CoinSelectionStrategy strategy,
  int changeSats = 10000,
  int feeSats = 200,
  double actualFeeRate = 1.0,
}) {
  return InputSelection(
    selectedUtxos: const [],
    sent: Amount(field0: BigInt.from(50000)),
    nSentOutputs: BigInt.one,
    change: Amount(field0: BigInt.from(changeSats)),
    nChangeOutputs: BigInt.from(changeSats > 0 ? 1 : 0),
    fee: Amount(field0: BigInt.from(feeSats)),
    actualFeeRate: actualFeeRate,
    strategy: strategy,
  );
}

void main() {
  group('pickDefaultSelection', () {
    final changeless =
        selection(strategy: CoinSelectionStrategy.changeless, changeSats: 0);
    final lowestFee = selection(strategy: CoinSelectionStrategy.lowestFee);
    final feeRateCap = selection(strategy: CoinSelectionStrategy.feeRateCap);
    final greedy = selection(strategy: CoinSelectionStrategy.greedy);
    final all = [greedy, feeRateCap, lowestFee, changeless];

    test('default mode prefers changeless', () {
      expect(pickDefaultSelection(all), changeless);
    });

    test('default mode prefers lowestFee without changeless', () {
      expect(pickDefaultSelection([greedy, feeRateCap, lowestFee]), lowestFee);
    });

    test('default mode prefers feeRateCap over greedy', () {
      expect(pickDefaultSelection([greedy, feeRateCap]), feeRateCap);
    });

    test('forceFeeRate prefers feeRateCap over everything else', () {
      expect(pickDefaultSelection(all, forceFeeRate: true), feeRateCap);
    });

    test('forceFeeRate prefers lowestFee when no exact-rate selection', () {
      expect(pickDefaultSelection([changeless, greedy, lowestFee], forceFeeRate: true),
          lowestFee);
    });

    test('forceFeeRate keeps changeless as last resort', () {
      expect(pickDefaultSelection([changeless, greedy], forceFeeRate: true),
          greedy);
      expect(pickDefaultSelection([changeless], forceFeeRate: true),
          changeless);
    });

    test('falls back to the first selection for unknown strategies', () {
      final drain = selection(strategy: CoinSelectionStrategy.drain, changeSats: 0);
      expect(pickDefaultSelection([drain]), drain);
    });

    test('throws on empty selections', () {
      expect(() => pickDefaultSelection([]), throwsException);
    });
  });
}
