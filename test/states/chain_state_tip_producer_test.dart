import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/structs/sync_progress_event.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// TICKET 1 (t_e67b63ae): single-producer chain tip.
///
/// The chain state's tip is writable through ONE chokepoint, and only the
/// active backend session may feed it. A stub second backend serving a
/// foreign tip (523, the 2026-11-13 incident value) must never move the tip
/// while the frigate session is the active producer, and with no session
/// tip the chain state goes stale — there is no fallback that substitutes
/// another backend's value. The public blindbit instance never appears in
/// these tests: the stub second backend is the injected chainHeightFn below
/// (a local stub, no network).
void main() {
  // Local stub second backend: whatever url it is asked about, it serves
  // the foreign tip 523.
  ChainState stubChain({int stubTip = 523}) => ChainState(
        chainHeightFn: ({required blindbitUrl}) async => stubTip,
        networkCheckFn: ({required blindbitUrl, required network}) async =>
            true,
      );

  group('chain-state tip-write surface (seam tests)', () {
    test('frigate-active + session tip -> accepted', () {
      final chain = stubChain()..initialize(Network.regtest);
      chain.setTipProducer(ChainTipProducer.frigateSession);

      chain.applySessionTip(522);

      expect(chain.available, true);
      expect(chain.tip, 522);
    });

    test('frigate-active + stub foreign tip -> rejected', () async {
      final chain = stubChain()..initialize(Network.regtest);
      chain.setTipProducer(ChainTipProducer.frigateSession);
      chain.applySessionTip(522);

      // What the startup path and the tip poller used to do against the
      // configured blindbit url — here the local stub serving 523.
      final connected = await chain.connect('http://stub-blindbit.invalid');
      await chain.updateChainTip();

      expect(connected, true); // the blindbit url record is kept, ...
      expect(chain.tip, 522); // ...but its tip never enters the state.
    });

    test('no session tip -> stale (and the blindbit poller stays off)',
        () async {
      final chain = stubChain()..initialize(Network.regtest);

      // Blindbit is the default producer on a fresh state: connect seeds a
      // tip.
      await chain.connect('http://stub-blindbit.invalid');
      expect(chain.available, true);

      // The frigate session becomes the active producer: the previously
      // sourced tip goes stale until the session delivers one — no
      // fallback substitutes the old value.
      chain.setTipProducer(ChainTipProducer.frigateSession);
      expect(chain.available, false);
      expect(() => chain.tip, throwsException);

      // The blindbit url poller must not run for the tip in this mode.
      chain.startChainPoller(false);
      expect(chain.pollerRunning, false);
    });

    test('blindbit-active + stub tip -> accepted (producer switch back)',
        () async {
      final chain = stubChain()..initialize(Network.regtest);
      chain.setTipProducer(ChainTipProducer.frigateSession);
      chain.applySessionTip(522);

      chain.setTipProducer(ChainTipProducer.blindbitPoller);
      await chain.connect('http://stub-blindbit.invalid');

      expect(chain.available, true);
      expect(chain.tip, 523);
      // The poller runs again in this mode.
      chain.startChainPoller(false);
      expect(chain.pollerRunning, true);
      chain.stopChainPoller();
    });
  });

  group('session tip stream routing (scan-progress events)', () {
    test('Tip events forward to the chain state even between scans', () {
      final chain = stubChain()..initialize(Network.regtest);
      chain.setTipProducer(ChainTipProducer.frigateSession);

      final progress = SyncProgressState.forTesting();
      progress.onSessionTip = chain.applySessionTip;

      // A frigate scan announces its tip first — with the bar inactive
      // (between scans) the tip must still reach the chain state.
      progress.handleEvent(const SyncProgressEvent_Tip(height: 522));

      expect(chain.available, true);
      expect(chain.tip, 522);
    });

    test('Tip events are rejected by the chain state in blindbit mode', () {
      final chain = stubChain()..initialize(Network.regtest);
      chain.setTipProducer(ChainTipProducer.blindbitPoller);

      final progress = SyncProgressState.forTesting();
      progress.onSessionTip = chain.applySessionTip;

      progress.handleEvent(const SyncProgressEvent_Tip(height: 522));

      expect(chain.available, false); // no blindbit connect happened
      expect(() => chain.tip, throwsException);
    });
  });
}
