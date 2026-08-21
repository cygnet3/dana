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
