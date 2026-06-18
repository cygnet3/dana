import 'package:danawallet/generated/rust/api/structs/state_update.dart';
import 'package:danawallet/services/sync_engine.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:danawallet/states/wallet_state.dart';

/// In-process equivalent of [SynchronizationTaskHandler].
///
/// Runs sync in the main isolate, so it works on Linux and as an Android
/// fallback when notification permission has not been granted. Sync stops
/// whenever the app is suspended by the OS — that trade-off is intentional.
class InProcessSyncService {
  final SyncEngine _engine;

  InProcessSyncService({
    required SyncProgressState syncProgress,
    required WalletState walletState,
  }) : _engine = SyncEngine(
          logTag: 'in-process',
          onSyncStarted: (start, end) {
            syncProgress.activate(start, end);
          },
          onSyncComplete: (success) => syncProgress.deactivate(success),
          onStateUpdate: (update) =>
              walletState.processUpdate(StateUpdate.decode(encoded: update)),
        );

  Future<void> trySync() => _engine.trySync();

  void dispose() => _engine.dispose();
}
