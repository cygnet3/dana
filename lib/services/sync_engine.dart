import 'dart:async';
import 'dart:io' as io show pid;

import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/extensions/outpoint.dart';
import 'package:danawallet/generated/rust/api/chain.dart';
import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/structs/frigate_scan_outcome.dart';
import 'package:danawallet/generated/rust/api/structs/outpoint.dart';
import 'package:danawallet/generated/rust/api/structs/state_update.dart';
import 'package:danawallet/generated/rust/api/wallet/frigate.dart'
    show frigateTipProbe;
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/repositories/owned_outputs_repository.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/transactions_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:logger/logger.dart';

/// Platform-agnostic sync core.
///
/// Owns the [createSyncResultStream] subscription and the [trySync] logic.
/// All platform-specific side effects (IPC messages, progress bar updates,
/// UI state refreshes) are injected as callbacks so this class stays free of
/// Flutter and android-plugin dependencies and can run safely in both the
/// main isolate and a background isolate.
class SyncEngine {
  /// Called just before [wallet.syncToHeight] or [wallet.syncViaFrigate]
  /// begins.
  final void Function(int startHeight, int endHeight) onSyncStarted;

  /// Called when the active sync call finishes or throws. [success] is false
  /// on error so callers can deactivate progress indicators in both cases.
  final void Function(bool success) onSyncComplete;

  /// Called after each [StateUpdate] to refresh UI state from the DB.
  final Future<void> Function(bool lastSyncOnly) onStateUpdated;

  /// Called when the frigate backend is unreachable — probe failure at wake
  /// or a scan that ended [FrigateScanOutcome_Disconnected] — so the host can
  /// surface a neutral transient banner (D8). Optional: hosts without a
  /// banner surface simply log.
  final void Function(String message)? onTransientOffline;

  final String _logTag;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;
  Completer<void>? _idleCompleter;

  /// True only while a frigate scan is running in this isolate (single-writer
  /// rule for the scan-session keys, D2).
  bool _frigateScanRunning = false;

  /// Current process id — the scan-lock liveness marker (D2). The background
  /// service isolate shares the app process, so it writes the same pid.
  int get pid => io.pid;

  late final StreamSubscription _syncResultSubscription;

  final _ownedOutputsRepository = OwnedOutputsRepository.instance;
  final _transactionsRepository = TransactionsRepository.instance;
  final _walletRepository = WalletRepository.instance;

  SyncEngine({
    required this.onSyncStarted,
    required this.onSyncComplete,
    required this.onStateUpdated,
    this.onTransientOffline,
    String logTag = 'sync',
  }) : _logTag = logTag {
    _syncResultSubscription = createSyncResultStream().listen(_onSyncResult);
  }

  Future<void> _onSyncResult(StateUpdate event) async {
    // Process found outputs (new UTXOs we own)
    for (final found in event.foundOutputs) {
      // first, insert the transaction data in the known transactions table
      await _transactionsRepository.addIncomingTransaction(
        txid: found.outpoint.txid,
        confirmationHeight: event.blkheight,
        confirmationBlockhash: event.blkhash,
      );

      // Insert output into database
      await _ownedOutputsRepository.insertOutput(output: found);
    }

    List<OutPoint> unknownSpends = [];

    // Process found inputs (our UTXOs being spent)
    for (final outpoint in event.foundInputs) {
      // Try to confirm an outgoing transaction
      final confirmed =
          await _transactionsRepository.confirmOutgoingTransaction(
        confirmedOutpointTxid: outpoint.txid,
        confirmedOutpointVout: outpoint.vout,
        confirmationHeight: event.blkheight,
        confirmationBlockhash: event.blkhash,
      );

      // this output does not have an associated transaction
      // this can occur if a user imported their seed phrase in multiple wallets
      // generally we should discourage this, but it's inevitable that it will happen
      if (!confirmed) {
        unknownSpends.add(outpoint);
      }
    }

    if (unknownSpends.isNotEmpty) {
      Logger().w(
          "Unknown spends detected, marking the following outpoints as spent: ${unknownSpends.toDisplayString()}");
      await _transactionsRepository.addOutgoingTransaction(
        spentOutpoints: unknownSpends,
        recipients: [],
        txid: null,
        confirmationHeight: event.blkheight,
        confirmationBlockhash: event.blkhash,
      );
    }

    await _walletRepository.saveLastSync(event.blkheight);

    // keep the scan-session heartbeat fresh while a frigate scan is running
    if (_frigateScanRunning) {
      await _walletRepository.touchFrigateScanBeat();
    }

    if (event.foundOutputs.isNotEmpty || event.foundInputs.isNotEmpty) {
      await onStateUpdated(false);
    } else {
      await onStateUpdated(true);
    }
  }

  Future<void> trySync() async {
    if (_isSyncing) {
      Logger().i('[$_logTag] sync already in progress, skipping');
      return;
    }
    _isSyncing = true;
    try {
      final wallet = await _walletRepository.readWallet();
      if (wallet == null) {
        Logger().i('[$_logTag] no wallet, skipping');
        return;
      }

      final network = await _walletRepository.readNetwork();
      final settings = SettingsRepository.instance;
      final blindbitUrl =
          await settings.getBlindbitUrl() ?? network.defaultBlindbitUrl;

      // Frigate backend override: an unset or empty frigate URL keeps the
      // blindbit backend as the default.
      final frigateUrl = (await settings.getFrigateUrl())?.trim();
      final useFrigate = frigateUrl != null && frigateUrl.isNotEmpty;

      int? tip;
      String? probeTipHash;
      if (useFrigate) {
        // A scan lock present while this engine is not syncing was left by a
        // killed process (D2): clear it and resume from lastSync — the
        // scanner start_height prevents history re-sweeping.
        await _clearStaleFrigateScanLock();

        // Server-authoritative catch-up (D3): fetch the chain tip keylessly
        // before anything else — before watch-set collection, before bar
        // activation. Failure maps to the D8 transient-offline path: no
        // subscribe, no scan, no watch-set disclosure, checkpoint untouched;
        // the next wake auto-resumes.
        try {
          final probe = await frigateTipProbe(url: frigateUrl);
          tip = probe.$1;
          probeTipHash = probe.$2;
        } catch (e) {
          Logger().w('[$_logTag] frigate unreachable: $e');
          onTransientOffline?.call(frigateOfflineMsg);
          return;
        }
      } else {
        final correctNetwork =
            await checkNetwork(blindbitUrl: blindbitUrl, network: network);
        if (!correctNetwork) {
          Logger().w('[$_logTag] wrong network, skipping');
          return;
        }

        tip = await getChainHeight(blindbitUrl: blindbitUrl);
      }

      var lastSync = await _walletRepository.readLastSync();

      if (lastSync == null) {
        lastSync = await _heightFromBirthday(network);
        await _walletRepository.saveLastSync(lastSync);
        Logger()
            .i('[$_logTag] initialized lastSync to birthday height $lastSync');
      }

      if (lastSync >= tip) {
        // Idle wake (D3): up to date in BOTH backends. For frigate this is
        // the fix for the never-resolving bar and the per-wake re-disclosure:
        // no subscribe, no scan, no getWatchedOutputs call.
        Logger().i('[$_logTag] up to date (lastSync=$lastSync tip=$tip)');
        return;
      }

      Logger()
          .i('[$_logTag] syncing $lastSync -> $tip');

      final dustLimit = await settings.getDustLimit() ?? defaultDustLimit;

      // The probe/getChainHeight tip gives the bar a real end height up
      // front, so it can become determinate as soon as scanner Heights
      // arrive (D4).
      onSyncStarted(lastSync + 1, tip);

      if (useFrigate) {
        // Single-writer (D2): only this isolate, which runs the scan, writes
        // the session keys.
        await _walletRepository.beginFrigateScan(pid: pid);
        _frigateScanRunning = true;
        try {
          // Watched outputs carry script bytes so the scanner re-subscribes
          // them on start: unspent + unconfirmed-spent outputs, mirroring the
          // blindbit scan list. This is the single disclosure point —
          // reached only when a scan will actually run (D3).
          final watchedOutputs =
              await _ownedOutputsRepository.getWatchedOutputs();

          final outcome = await wallet.syncViaFrigate(
              frigateUrl: frigateUrl,
              fromHeight: lastSync + 1,
              dustLimit: BigInt.from(dustLimit),
              watchedOutputs: watchedOutputs);

          // Persist the last tip pair (diagnostics + the D9 boundary record;
          // never drives the checkpoint) and clear the lock whatever the
          // outcome was.
          await _walletRepository.endFrigateScan(
              tipHeight: tip, tipHash: probeTipHash);

          switch (outcome) {
            case FrigateScanOutcome_Completed():
              break;
            case FrigateScanOutcome_Disconnected(:final reason):
              // D8: the checkpoint already advanced to the last Confirmed
              // boundary via the pump; a normal end with a neutral banner.
              // No error path, no blindbit fallback.
              Logger().w('[$_logTag] frigate scan ended early: $reason');
              onTransientOffline?.call(frigateOfflineMsg);
          }
        } catch (_) {
          await _walletRepository.endFrigateScan(
              tipHeight: tip, tipHash: probeTipHash);
          rethrow;
        } finally {
          _frigateScanRunning = false;
        }
      } else {
        final unconfirmedSpentOutpoints =
            await _transactionsRepository.getUnconfirmedSpentOutpoints();
        final unspentOutpoints =
            await _ownedOutputsRepository.getUnspentOutpoints();
        final ownedOutpoints = [
          ...unconfirmedSpentOutpoints,
          ...unspentOutpoints
        ];

        await wallet.syncToHeight(
            fromHeight: lastSync + 1,
            toHeight: tip,
            blindbitUrl: blindbitUrl,
            dustLimit: BigInt.from(dustLimit),
            ownedOutpoints: ownedOutpoints);
      }

      Logger().i('[$_logTag] sync complete');
      onSyncComplete(true);
    } catch (e) {
      Logger().e('[$_logTag] sync error: $e');
      onSyncComplete(false);
    } finally {
      _isSyncing = false;
      _idleCompleter?.complete();
      _idleCompleter = null;
    }
  }

  /// Clears a frigate scan lock found at wake time. Since [trySync] runs the
  /// scan synchronously in this isolate, any lock present here is by
  /// construction orphaned (its process died, or its beat went stale).
  Future<void> _clearStaleFrigateScanLock() async {
    final lock = await _walletRepository.readFrigateScanLock();
    if (lock == null) return;
    Logger().w('[$_logTag] clearing stale frigate scan lock '
        '(pid=${lock.pid}, stale=${lock.isStale(currentPid: pid)})');
    await _walletRepository.endFrigateScan();
  }

  /// Waits until any active [trySync] call has fully unwound, including its
  /// [onSyncComplete] callback. Returns immediately if idle.
  ///
  /// [timeout] guards against Rust taking too long to honour [interruptSync].
  Future<void> waitForIdle({
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (!_isSyncing) return Future.value();
    _idleCompleter ??= Completer<void>();
    return _idleCompleter!.future.timeout(timeout, onTimeout: () {});
  }

  Future<int> _heightFromBirthday(network) async {
    final birthday = await _walletRepository.readBirthday() ?? defaultBirthday;
    final mempoolApi = MempoolApiRepository(network: network);
    final block = await mempoolApi.getBlockFromTimestamp(birthday.toSeconds());
    return block.height;
  }

  void dispose() {
    _syncResultSubscription.cancel();
  }
}
