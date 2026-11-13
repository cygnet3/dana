import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/wallet/frigate.dart';
import 'package:danawallet/services/backend_switch_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// TICKET 2 (t_47fd1638): backend-switch gate v1 — refuse, don't reconcile.
///
/// A switch is accepted only when the new backend's tip EXACTLY equals the
/// stored (single-producer) tip. On mismatch the switch is refused with the
/// v1 error message and the wallet stays on the current backend. Switching
/// with unconfirmed spends is blocked outright. No auto-repair, no rescan
/// machinery, no tolerance window in v1. A freshly restarted trailing
/// frigate (probe tip behind the stored tip) is refused until caught up —
/// that is correct behavior, not a bug.
///
/// All backend I/O is injected: the probe fns are local stubs, no network.
void main() {
  const mismatchMessage =
      'new backend seems inconsistent with existing history — check it '
      'follows the same chain and try again';

  FrigateTipProbe probe(int height, {Network network = Network.regtest}) =>
      FrigateTipProbe(
          tipHeight: height, tipHash: 'hash$height', network: network);

  BackendSwitchGate gateWith({
    Object? frigateTip, // int tip, an Error to throw, or null = fail if called
    Object? unconfirmedSpends,
    Network probeNetwork = Network.regtest,
  }) {
    return BackendSwitchGate(
      frigateTipProbeFn: ({required url}) async {
        final t = frigateTip;
        if (t is Error) throw t;
        expect(t, isNotNull,
            reason: 'probe must not be consulted before the spend gate');
        return probe(t as int, network: probeNetwork);
      },
      blindbitTipFn: ({required blindbitUrl}) async => 523,
      unconfirmedSpentCountFn: () async => unconfirmedSpends is Error
          ? throw unconfirmedSpends
          : (unconfirmedSpends as int? ?? 0),
    );
  }

  group('backend-switch gate v1 (seam tests)', () {
    test('unconfirmed spends block the switch; probe never consulted',
        () async {
      final probeCalled = <int>[];
      final gate = BackendSwitchGate(
        frigateTipProbeFn: ({required url}) async {
          probeCalled.add(1);
          return probe(523);
        },
        blindbitTipFn: ({required blindbitUrl}) async => 523,
        unconfirmedSpentCountFn: () async => 1,
      );

      final result = await gate.evaluate(
        targetBackend: 'frigate',
        frigateUrl: '127.0.0.1:50002',
        blindbitUrl: 'http://stub.invalid',
        storedTip: 522,
        network: Network.regtest,
      );

      expect(result.allowed, isFalse);
      expect(result.error, BackendSwitchGate.unconfirmedSpendsMessage);
      expect(probeCalled, isEmpty,
          reason: 'the spend gate fires before any backend probe');
    });

    test('tip mismatch refused with the exact v1 message', () async {
      final result = await gateWith(frigateTip: 523).evaluate(
        targetBackend: 'frigate',
        frigateUrl: '127.0.0.1:50002',
        blindbitUrl: 'http://stub.invalid',
        storedTip: 522,
        network: Network.regtest,
      );

      expect(result.allowed, isFalse);
      expect(result.error, mismatchMessage);
    });

    test('exact tip match allowed', () async {
      final result = await gateWith(frigateTip: 523).evaluate(
        targetBackend: 'frigate',
        frigateUrl: '127.0.0.1:50002',
        blindbitUrl: 'http://stub.invalid',
        storedTip: 523,
        network: Network.regtest,
      );

      expect(result.allowed, isTrue);
      expect(result.error, isNull);
    });

    test('foreign-chain probe refused even at an equal height', () async {
      final result =
          await gateWith(frigateTip: 522, probeNetwork: Network.mainnet)
              .evaluate(
        targetBackend: 'frigate',
        frigateUrl: '127.0.0.1:50002',
        blindbitUrl: 'http://stub.invalid',
        storedTip: 522,
        network: Network.regtest,
      );

      expect(result.allowed, isFalse);
      expect(result.error, mismatchMessage);
    });

    test('blindbit target: mismatch refused, exact match allowed', () async {
      final refused = await gateWith().evaluate(
        targetBackend: 'blindbit',
        frigateUrl: null,
        blindbitUrl: 'http://stub.invalid',
        storedTip: 522,
        network: Network.regtest,
      );
      expect(refused.allowed, isFalse);
      expect(refused.error, mismatchMessage);

      final allowed = await BackendSwitchGate(
        frigateTipProbeFn: ({required url}) async => probe(523),
        blindbitTipFn: ({required blindbitUrl}) async => 522,
        unconfirmedSpentCountFn: () async => 0,
      ).evaluate(
        targetBackend: 'blindbit',
        frigateUrl: null,
        blindbitUrl: 'http://stub.invalid',
        storedTip: 522,
        network: Network.regtest,
      );
      expect(allowed.allowed, isTrue);
    });

    test('unreachable backend refused with a cleaned message', () async {
      final result =
          await gateWith(frigateTip: StateError('connection refused')).evaluate(
        targetBackend: 'frigate',
        frigateUrl: '127.0.0.1:1',
        blindbitUrl: 'http://stub.invalid',
        storedTip: 522,
        network: Network.regtest,
      );

      expect(result.allowed, isFalse);
      expect(result.error, contains('Frigate unreachable'));
      expect(result.error, isNot(contains('AnyhowException')));
    });

    test('no stored tip: nothing to reconcile against — allowed (v1)',
        () async {
      final result = await gateWith(frigateTip: 523).evaluate(
        targetBackend: 'frigate',
        frigateUrl: '127.0.0.1:50002',
        blindbitUrl: 'http://stub.invalid',
        storedTip: null,
        network: Network.regtest,
      );

      expect(result.allowed, isTrue);
    });
  });
}
