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

  group('bestNoChangeSelection', () {
    test('returns null when every selection creates change', () {
      final withChange = selection(strategy: CoinSelectionStrategy.lowestFee);
      expect(bestNoChangeSelection([withChange]), isNull);
    });

    test('prefers the changeless strategy', () {
      final changeless = selection(
          strategy: CoinSelectionStrategy.changeless, changeSats: 0, feeSats: 300);
      final greedyNoChange = selection(
          strategy: CoinSelectionStrategy.greedy, changeSats: 0, feeSats: 100);
      expect(bestNoChangeSelection([greedyNoChange, changeless]), changeless);
    });

    test('otherwise picks the cheapest no-change selection', () {
      final pricey = selection(
          strategy: CoinSelectionStrategy.lowestFee, changeSats: 0, feeSats: 300);
      final cheap = selection(
          strategy: CoinSelectionStrategy.greedy, changeSats: 0, feeSats: 100);
      expect(bestNoChangeSelection([pricey, cheap]), cheap);
    });
  });

  group('buildFeeOptions', () {
    test('offers both options when the rates differ', () {
      // requested 1 sat/vB; changeless overshoots to 7.1
      final feeRateCap = selection(
          strategy: CoinSelectionStrategy.feeRateCap, actualFeeRate: 1.0);
      final changeless = selection(
          strategy: CoinSelectionStrategy.changeless,
          changeSats: 0,
          feeSats: 788,
          actualFeeRate: 7.1);
      final options = buildFeeOptions([feeRateCap, changeless], 1);
      expect(options.exact, feeRateCap);
      expect(options.noChange, changeless);
    });

    test('collapses to the no-change option when the rates round equal', () {
      // requested 7 sat/vB; changeless actual 7.09 rounds to 7
      final feeRateCap = selection(
          strategy: CoinSelectionStrategy.feeRateCap, actualFeeRate: 7.0);
      final changeless = selection(
          strategy: CoinSelectionStrategy.changeless,
          changeSats: 0,
          feeSats: 788,
          actualFeeRate: 7.09);
      final options = buildFeeOptions([feeRateCap, changeless], 7);
      expect(options.exact, changeless);
      expect(options.noChange, isNull);
    });

    test('single option when the exact selection already has no change', () {
      final feeRateCap = selection(
          strategy: CoinSelectionStrategy.feeRateCap,
          changeSats: 0,
          actualFeeRate: 1.0);
      final options = buildFeeOptions([feeRateCap], 1);
      expect(options.exact, feeRateCap);
      expect(options.noChange, isNull);
    });
  });
}
