import 'package:danawallet/generated/rust/api/structs/input_selection.dart';

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
  final preference = forceFeeRate
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
  for (final preferred in preference) {
    for (final selection in selections) {
      if (selection.strategy == preferred) {
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

/// The best selection without change output among [selections], if any:
/// the changeless-strategy selection in priority, otherwise the cheapest.
InputSelection? bestNoChangeSelection(List<InputSelection> selections) {
  final noChange =
      selections.where((s) => s.change.field0 == BigInt.zero).toList();
  if (noChange.isEmpty) {
    return null;
  }
  for (final selection in noChange) {
    if (selection.strategy == CoinSelectionStrategy.changeless) {
      return selection;
    }
  }
  noChange.sort((a, b) => a.fee.field0.compareTo(b.fee.field0));
  return noChange.first;
}

/// Build the fee options to present for a payment at an explicitly chosen
/// [feerate] (sat/vB), from the candidate [selections].
///
/// When the no-change selection's actual rate already rounds to [feerate],
/// it is the better deal (no change output to spend later), so it becomes
/// the only option presented.
FeeOptions buildFeeOptions(List<InputSelection> selections, int feerate) {
  var exact = pickDefaultSelection(selections, forceFeeRate: true);

  InputSelection? noChange;
  if (exact.change.field0 > BigInt.zero) {
    final candidate = bestNoChangeSelection(selections);
    if (candidate != null) {
      if (candidate.actualFeeRate.round() == feerate) {
        exact = candidate;
      } else {
        noChange = candidate;
      }
    }
  }

  return FeeOptions(exact: exact, noChange: noChange);
}
