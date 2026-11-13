import 'package:danawallet/generated/rust/api/chain.dart' show getChainHeight;
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/wallet/frigate.dart'
    show FrigateTipProbe, frigateTipProbe;
import 'package:danawallet/global_functions.dart' show exceptionToString;
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/transactions_repository.dart';
import 'package:danawallet/states/chain_state.dart' show ChainHeightFn;

/// Keyless frigate tip probe (the D10 settings probe — no scan key on this
/// path).
typedef FrigateTipProbeFn = Future<FrigateTipProbe> Function(
    {required String url});

/// Number of spends broadcast but not yet confirmed (v1 gate input).
typedef UnconfirmedSpentCountFn = Future<int> Function();

/// The verdict of a backend-switch gate evaluation (v1: refuse, never
/// reconcile). [error] is non-null exactly when the switch is refused and
/// is the message to surface to the user.
class BackendSwitchGateResult {
  final bool allowed;
  final String? error;

  const BackendSwitchGateResult.allowed()
      : allowed = true,
        error = null;

  const BackendSwitchGateResult.refused(this.error) : allowed = false;
}

/// TICKET 2 (t_47fd1638): gate backend switching — v1 reconciliation is
/// "refuse, don't reconcile".
///
/// Rules:
/// - Switching is BLOCKED while unconfirmed spends exist (a switch would
///   desynchronize the confirmation-tracking path from the backend that saw
///   the mempool entry).
/// - A switch is accepted only when the new backend's tip EXACTLY equals
///   the stored tip (the single-producer tip of t_e67b63ae). On mismatch —
///   including a freshly restarted trailing frigate that has not caught up
///   yet, and a backend following another chain — the switch is refused
///   with [tipMismatchMessage] and the caller keeps the current backend.
/// - No auto-repair, no rescan machinery, no tolerance window in v1.
///
/// All backend I/O is injectable so tests run against local stubs; the
/// default construction wires the real keyless probe paths.
class BackendSwitchGate {
  /// Verbatim v1 copy for a tip/chain mismatch (card t_47fd1638).
  static const String tipMismatchMessage =
      'new backend seems inconsistent with existing history — check it '
      'follows the same chain and try again';

  /// Verbatim v1 copy for a switch attempted with unconfirmed spends.
  static const String unconfirmedSpendsMessage =
      'Cannot switch backend while a spend is unconfirmed — wait for it to '
      'confirm and try again';

  final FrigateTipProbeFn frigateTipProbeFn;
  final ChainHeightFn blindbitTipFn;
  final UnconfirmedSpentCountFn unconfirmedSpentCountFn;

  BackendSwitchGate({
    FrigateTipProbeFn? frigateTipProbeFn,
    ChainHeightFn? blindbitTipFn,
    UnconfirmedSpentCountFn? unconfirmedSpentCountFn,
  })  : frigateTipProbeFn = frigateTipProbeFn ?? _defaultFrigateTipProbeFn,
        blindbitTipFn = blindbitTipFn ?? _defaultBlindbitTipFn,
        unconfirmedSpentCountFn =
            unconfirmedSpentCountFn ?? _defaultUnconfirmedSpentCountFn;

  static Future<FrigateTipProbe> _defaultFrigateTipProbeFn(
          {required String url}) =>
      frigateTipProbe(url: url);

  static Future<int> _defaultBlindbitTipFn({required String blindbitUrl}) =>
      getChainHeight(blindbitUrl: blindbitUrl);

  static Future<int> _defaultUnconfirmedSpentCountFn() async =>
      (await TransactionsRepository.instance.getUnconfirmedSpentOutpoints())
          .length;

  /// Evaluate a switch to [targetBackend] ('blindbit' | 'frigate').
  ///
  /// [storedTip] is the current single-producer tip (null when the chain
  /// state has none yet — a wallet with no tip has no history to reconcile
  /// against, so the tip check is vacuous and the switch is allowed; the
  /// single-producer chokepoint still protects the tip after the switch).
  Future<BackendSwitchGateResult> evaluate({
    required String targetBackend,
    required String? frigateUrl,
    required String? blindbitUrl,
    required int? storedTip,
    required Network network,
  }) async {
    // Spend gate first: never touch a backend while a spend is in flight.
    final unconfirmedSpends = await unconfirmedSpentCountFn();
    if (unconfirmedSpends > 0) {
      return const BackendSwitchGateResult.refused(unconfirmedSpendsMessage);
    }

    if (storedTip == null) {
      return const BackendSwitchGateResult.allowed();
    }

    try {
      if (targetBackend == frigateBackendFrigate) {
        if (frigateUrl == null || frigateUrl.isEmpty) {
          return const BackendSwitchGateResult.refused(
              'Set a frigate url before switching to the frigate backend');
        }
        final probe = await frigateTipProbeFn(url: frigateUrl);
        if (probe.network != network) {
          return const BackendSwitchGateResult.refused(tipMismatchMessage);
        }
        if (probe.tipHeight != storedTip) {
          return const BackendSwitchGateResult.refused(tipMismatchMessage);
        }
        return const BackendSwitchGateResult.allowed();
      }

      // blindbit target: probe its tip through the same exact-match rule.
      final url = blindbitUrl;
      if (url == null || url.isEmpty) {
        return const BackendSwitchGateResult.refused(
            'No blindbit url configured');
      }
      final tip = await blindbitTipFn(blindbitUrl: url);
      if (tip != storedTip) {
        return const BackendSwitchGateResult.refused(tipMismatchMessage);
      }
      return const BackendSwitchGateResult.allowed();
    } catch (e) {
      final backendName =
          targetBackend == frigateBackendFrigate ? 'Frigate' : 'Blindbit';
      return BackendSwitchGateResult.refused(
          '$backendName unreachable: ${exceptionToString(e)}');
    }
  }
}
