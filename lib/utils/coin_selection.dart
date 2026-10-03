import 'package:danawallet/generated/rust/api/structs/input_selection.dart';

/// Display/decision fields from an [InputSelection], for pure helpers and tests.
class SelectionMetrics {
  final CoinSelectionStrategy? strategy;
  final BigInt change;
  final BigInt fee;
  final double actualFeeRate;

  const SelectionMetrics({
    required this.strategy,
    required this.change,
    required this.fee,
    required this.actualFeeRate,
  });

  SelectionMetrics.fromSelection(InputSelection selection)
      : strategy = selection.strategy,
        change = selection.change.field0,
        fee = selection.fee.field0,
        actualFeeRate = selection.actualFeeRate;
}

/// Preference order for [pickDefaultSelection] / [pickDefaultStrategy].
List<CoinSelectionStrategy> preferenceOrder({bool forceFeeRate = false}) {
  return forceFeeRate
      ? const [
          CoinSelectionStrategy.feeRateCap,
          CoinSelectionStrategy.lowestFee,
          CoinSelectionStrategy.greedy,
          CoinSelectionStrategy.changeless,
        ]
      : const [
          CoinSelectionStrategy.changeless,
          CoinSelectionStrategy.lowestFee,
          CoinSelectionStrategy.feeRateCap,
          CoinSelectionStrategy.greedy,
        ];
}

CoinSelectionStrategy? pickDefaultStrategy(
  List<CoinSelectionStrategy?> strategies, {
  bool forceFeeRate = false,
}) {
  for (final preferred in preferenceOrder(forceFeeRate: forceFeeRate)) {
    if (strategies.contains(preferred)) {
      return preferred;
    }
  }
  for (final strategy in strategies) {
    if (strategy != null) {
      return strategy;
    }
  }
  return null;
}

/// Pick the preferred selection from the candidates produced by the
/// coin-selection strategies.
///
/// By default a changeless transaction is preferred (no change output to
/// fingerprint), then the lowest fee, then the exact-rate (fee rate cap)
/// selection, then the greedy fallback.
///
/// When [forceFeeRate] is set (the user explicitly chose a fee rate), the
/// exact-rate selection — which spdk only produces when the requested rate
/// can be honored — is preferred, then lowest fee, then greedy; a
/// changeless selection comes last, as it may exceed the requested rate.
InputSelection pickDefaultSelection(List<InputSelection> selections,
    {bool forceFeeRate = false}) {
  final chosen = pickDefaultStrategy(
    selections.map((s) => s.strategy).toList(),
    forceFeeRate: forceFeeRate,
  );
  if (chosen != null) {
    for (final selection in selections) {
      if (selection.strategy == chosen) {
        return selection;
      }
    }
  }
  if (selections.isEmpty) {
    throw Exception('No coin selection strategy succeeded');
  }
  return selections.first;
}

/// The fee options for a payment at an explicitly chosen fee rate.
///
/// [exact] is the selection that honors the requested fee rate. [noChange]
/// is a selection without change output (the remainder goes to the fee),
/// present only when it differs meaningfully from [exact]: it can be
/// cheaper than creating a change output now and paying to spend it again
/// later.
class FeeOptions {
  final InputSelection exact;
  final InputSelection? noChange;

  FeeOptions({required this.exact, this.noChange});
}

/// Index of the best no-change metrics entry, if any: changeless strategy
/// first, otherwise the cheapest.
int? bestNoChangeMetricsIndex(List<SelectionMetrics> selections) {
  final noChangeIndexes = <int>[];
  for (var i = 0; i < selections.length; i++) {
    if (selections[i].change == BigInt.zero) {
      noChangeIndexes.add(i);
    }
  }
  if (noChangeIndexes.isEmpty) {
    return null;
  }
  for (final i in noChangeIndexes) {
    if (selections[i].strategy == CoinSelectionStrategy.changeless) {
      return i;
    }
  }
  noChangeIndexes
      .sort((a, b) => selections[a].fee.compareTo(selections[b].fee));
  return noChangeIndexes.first;
}

/// The best selection without change output among [selections], if any:
/// the changeless-strategy selection in priority, otherwise the cheapest.
InputSelection? bestNoChangeSelection(List<InputSelection> selections) {
  final index = bestNoChangeMetricsIndex(
      selections.map(SelectionMetrics.fromSelection).toList());
  return index == null ? null : selections[index];
}

/// Decide exact vs optional no-change option from metrics.
///
/// Returns `(exactIndex, noChangeIndex?)`.
(int, int?) feeOptionIndexes(List<SelectionMetrics> selections, int feerate) {
  final chosen = pickDefaultStrategy(
    selections.map((s) => s.strategy).toList(),
    forceFeeRate: true,
  );
  var exactIndex = 0;
  if (chosen != null) {
    exactIndex = selections.indexWhere((s) => s.strategy == chosen);
    if (exactIndex < 0) {
      exactIndex = 0;
    }
  }

  if (selections[exactIndex].change > BigInt.zero) {
    final noChangeIndex = bestNoChangeMetricsIndex(selections);
    if (noChangeIndex != null) {
      if (selections[noChangeIndex].actualFeeRate.round() == feerate) {
        return (noChangeIndex, null);
      }
      return (exactIndex, noChangeIndex);
    }
  }
  return (exactIndex, null);
}

/// Build the fee options to present for a payment at an explicitly chosen
/// [feerate] (sat/vB), from the candidate [selections].
///
/// When the no-change selection's actual rate already rounds to [feerate],
/// it is the better deal (no change output to spend later), so it becomes
/// the only option presented.
FeeOptions buildFeeOptions(List<InputSelection> selections, int feerate) {
  final (exactIndex, noChangeIndex) = feeOptionIndexes(
      selections.map(SelectionMetrics.fromSelection).toList(), feerate);
  return FeeOptions(
    exact: selections[exactIndex],
    noChange: noChangeIndex == null ? null : selections[noChangeIndex],
  );
}
