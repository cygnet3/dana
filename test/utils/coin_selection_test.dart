import 'package:danawallet/generated/rust/api/structs/input_selection.dart';
import 'package:danawallet/utils/coin_selection.dart';
import 'package:flutter_test/flutter_test.dart';

SelectionMetrics metrics({
  required CoinSelectionStrategy strategy,
  int changeSats = 10000,
  int feeSats = 200,
  double actualFeeRate = 1.0,
}) {
  return SelectionMetrics(
    strategy: strategy,
    change: BigInt.from(changeSats),
    fee: BigInt.from(feeSats),
    actualFeeRate: actualFeeRate,
  );
}

void main() {
  group('pickDefaultStrategy', () {
    final all = [
      CoinSelectionStrategy.greedy,
      CoinSelectionStrategy.feeRateCap,
      CoinSelectionStrategy.lowestFee,
      CoinSelectionStrategy.changeless,
    ];

    test('default mode prefers changeless', () {
      expect(pickDefaultStrategy(all), CoinSelectionStrategy.changeless);
    });

    test('default mode prefers lowestFee without changeless', () {
      expect(
        pickDefaultStrategy([
          CoinSelectionStrategy.greedy,
          CoinSelectionStrategy.feeRateCap,
          CoinSelectionStrategy.lowestFee,
        ]),
        CoinSelectionStrategy.lowestFee,
      );
    });

    test('default mode prefers feeRateCap over greedy', () {
      expect(
        pickDefaultStrategy([
          CoinSelectionStrategy.greedy,
          CoinSelectionStrategy.feeRateCap,
        ]),
        CoinSelectionStrategy.feeRateCap,
      );
    });

    test('forceFeeRate prefers feeRateCap over everything else', () {
      expect(
        pickDefaultStrategy(all, forceFeeRate: true),
        CoinSelectionStrategy.feeRateCap,
      );
    });

    test('forceFeeRate prefers lowestFee when no exact-rate selection', () {
      expect(
        pickDefaultStrategy([
          CoinSelectionStrategy.changeless,
          CoinSelectionStrategy.greedy,
          CoinSelectionStrategy.lowestFee,
        ], forceFeeRate: true),
        CoinSelectionStrategy.lowestFee,
      );
    });

    test('forceFeeRate keeps changeless as last resort', () {
      expect(
        pickDefaultStrategy([
          CoinSelectionStrategy.changeless,
          CoinSelectionStrategy.greedy,
        ], forceFeeRate: true),
        CoinSelectionStrategy.greedy,
      );
      expect(
        pickDefaultStrategy([CoinSelectionStrategy.changeless],
            forceFeeRate: true),
        CoinSelectionStrategy.changeless,
      );
    });

    test('returns null on empty strategies', () {
      expect(pickDefaultStrategy([]), isNull);
    });
  });

  group('bestNoChangeMetricsIndex', () {
    test('returns null when every selection creates change', () {
      final withChange = metrics(strategy: CoinSelectionStrategy.lowestFee);
      expect(bestNoChangeMetricsIndex([withChange]), isNull);
    });

    test('prefers the changeless strategy', () {
      final changeless = metrics(
          strategy: CoinSelectionStrategy.changeless,
          changeSats: 0,
          feeSats: 300);
      final greedyNoChange = metrics(
          strategy: CoinSelectionStrategy.greedy, changeSats: 0, feeSats: 100);
      expect(bestNoChangeMetricsIndex([greedyNoChange, changeless]), 1);
    });

    test('otherwise picks the cheapest no-change selection', () {
      final pricey = metrics(
          strategy: CoinSelectionStrategy.lowestFee,
          changeSats: 0,
          feeSats: 300);
      final cheap = metrics(
          strategy: CoinSelectionStrategy.greedy, changeSats: 0, feeSats: 100);
      expect(bestNoChangeMetricsIndex([pricey, cheap]), 1);
    });
  });

  group('feeOptionIndexes', () {
    test('offers both options when the rates differ', () {
      // requested 1 sat/vB; changeless overshoots to 7.1
      final feeRateCap = metrics(
          strategy: CoinSelectionStrategy.feeRateCap, actualFeeRate: 1.0);
      final changeless = metrics(
          strategy: CoinSelectionStrategy.changeless,
          changeSats: 0,
          feeSats: 788,
          actualFeeRate: 7.1);
      final (exact, noChange) = feeOptionIndexes([feeRateCap, changeless], 1);
      expect(exact, 0);
      expect(noChange, 1);
    });

    test('collapses to the no-change option when the rates round equal', () {
      // requested 7 sat/vB; changeless actual 7.09 rounds to 7
      final feeRateCap = metrics(
          strategy: CoinSelectionStrategy.feeRateCap, actualFeeRate: 7.0);
      final changeless = metrics(
          strategy: CoinSelectionStrategy.changeless,
          changeSats: 0,
          feeSats: 788,
          actualFeeRate: 7.09);
      final (exact, noChange) = feeOptionIndexes([feeRateCap, changeless], 7);
      expect(exact, 1);
      expect(noChange, isNull);
    });

    test('single option when the exact selection already has no change', () {
      final feeRateCap = metrics(
          strategy: CoinSelectionStrategy.feeRateCap,
          changeSats: 0,
          actualFeeRate: 1.0);
      final (exact, noChange) = feeOptionIndexes([feeRateCap], 1);
      expect(exact, 0);
      expect(noChange, isNull);
    });
  });
}
