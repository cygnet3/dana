import 'package:danawallet/generated/rust/api/structs/sync_progress_event.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// D4/D10 acceptance: bar stages. The bar is indeterminate (progress null)
/// from activation until both the tip-driven end height and a first scanner
/// Height have arrived; it is determinate from the first Height after the
/// Tip (never interpolated); it is hidden (progress null, isSyncing false)
/// once the sync completes via deactivate().
void main() {
  group('SyncProgressState bar stages (D4)', () {
    test(
        'indeterminate at activation, determinate from first Height after Tip, hidden on deactivate',
        () {
      final state = SyncProgressState.forTesting();

      state.activate(100, 200);
      expect(state.isSyncing, true);
      // Stage 1 — indeterminate: no scanner Height yet, never interpolated.
      expect(state.progress, isNull);

      // A tip alone (even a scanner tip superseding the probe tip) must not
      // fabricate a fraction.
      state.handleEvent(const SyncProgressEvent_Tip(height: 250));
      expect(state.progress, isNull);

      // Stage 2 — determinate: first Height after the Tip.
      state.handleEvent(const SyncProgressEvent_Height(175));
      expect(state.progress, closeTo((175 - 100) / (250 - 100), 1e-9));

      // Heights at/after the end never overshoot the bar.
      state.handleEvent(const SyncProgressEvent_Height(300));
      expect(state.progress, closeTo((175 - 100) / (250 - 100), 1e-9));

      // Stage 3 — Completed: deactivate() hides the bar.
      state.deactivate(true);
      expect(state.isSyncing, false);
      expect(state.progress, isNull);
    });

    test('events after deactivate are ignored (no bar re-activation)', () {
      final state = SyncProgressState.forTesting();
      state.activate(100, 200);
      state.deactivate(true);

      // Trailing rust event after completion must not re-activate the bar.
      state.handleEvent(const SyncProgressEvent_Height(150));
      expect(state.isSyncing, false);
      expect(state.progress, isNull);
    });

    test(
        'degenerate end <= start stays indeterminate instead of dividing by zero',
        () {
      final state = SyncProgressState.forTesting();
      state.activate(100, 100);
      state.handleEvent(const SyncProgressEvent_Height(100));
      expect(state.progress, isNull);
    });
  });
}
