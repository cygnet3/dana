import 'dart:async';
import 'dart:io' as io show pid;

import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/extensions/outpoint.dart';
import 'package:danawallet/generated/rust/api/chain.dart';
import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/structs/frigate_scan_outcome.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/structs/outpoint.dart';
import 'package:danawallet/generated/rust/api/structs/state_update.dart';
import 'package:danawallet/generated/rust/api/wallet/frigate.dart'
    show FrigateTipProbe, WatchedOutput, frigateTipProbe;
// The engine's own stopFrigateMonitor() method shadows the generated
// top-level fn inside the class, so the bridge call gets its own prefix.
import 'package:danawallet/generated/rust/api/wallet/frigate.dart'
    as frigate_api show stopFrigateMonitor, frigateMonitorRunning;
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
///
/// External effects (rust probe/scan calls, watch-set collection, blindbit
/// chain calls) are injected as functions defaulting to the real
/// implementations, so acceptance tests can drive the wake flow with
/// counting fakes and no rust library.

/// Keyless tip probe (`frigateTipProbe` in the rust layer). Returns the tip
/// pair AND the chain the backend follows (genesis identification), so the
/// wake flow can refuse a foreign-chain backend before any scan.
typedef FrigateTipProbeFn = Future<FrigateTipProbe> Function(
    {required String url});

/// One-shot frigate scan (`SpWallet.syncViaFrigate`).
typedef FrigateScanFn = Future<FrigateScanOutcome> Function({
  required String frigateUrl,
  required int fromHeight,
  required BigInt dustLimit,
  required List<WatchedOutput> watchedOutputs,
});

/// Watch-set collection (`OwnedOutputsRepository.getWatchedOutputs`) — the
/// single watch-set disclosure point.
typedef WatchedOutputsFn = Future<List<WatchedOutput>> Function();

/// Continuous frigate monitor start (`SpWallet.startFrigateMonitor`): opens
/// the persistent key-bearing subscription for the phase-2 mempool tail.
typedef FrigateMonitorStartFn = Future<void> Function({
  required String frigateUrl,
  required int fromHeight,
  required BigInt dustLimit,
  required List<WatchedOutput> watchedOutputs,
});

/// Continuous frigate monitor stop (`SpWallet.stopFrigateMonitor`).
typedef FrigateMonitorStopFn = Future<void> Function();

/// Monitor liveness probe (rust `frigateMonitorRunning`): true while the
/// monitor task holds the subscription.
typedef FrigateMonitorActiveFn = Future<bool> Function();

/// Blindbit chain height (`getChainHeight`).
typedef ChainHeightFn = Future<int> Function({required String blindbitUrl});

/// Blindbit network check (`checkNetwork`).
typedef NetworkCheckFn = Future<bool> Function({
  required String blindbitUrl,
  required Network network,
});

/// Sync-result stream factory (`createSyncResultStream`).
typedef SyncResultStreamFn = Stream<StateUpdate> Function();

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

  /// True while the continuous frigate monitor (phase-2 tail) is running in
  /// this isolate. The rust-side task state ([frigateMonitorActive]) is the
  /// cross-isolate liveness truth.
  bool _frigateMonitorRunning = false;

  /// Periodic scan-session heartbeat while the monitor holds the
  /// subscription.
  Timer? _monitorBeatTimer;

  /// Current process id — the scan-lock liveness marker (D2). The background
  /// service isolate shares the app process, so it writes the same pid.
  int get pid => io.pid;

  late final StreamSubscription _syncResultSubscription;

  final WalletStore walletRepository;
  final SettingsStore settingsRepository;
  final FrigateTipProbeFn frigateProbe;
  final WatchedOutputsFn watchedOutputsFn;
  final FrigateScanFn frigateScanFn;
  final FrigateMonitorStartFn frigateMonitorStart;
  final FrigateMonitorStopFn frigateMonitorStop;
  final FrigateMonitorActiveFn frigateMonitorActive;
  final ChainHeightFn chainHeightFn;
  final NetworkCheckFn networkCheckFn;
  final SyncResultStreamFn syncResultStreamFn;

  /// Heartbeat interval for the monitor's scan-session beat. Null disables
  /// the timer (tests drive liveness through the session state directly).
  final Duration? monitorBeatInterval;

  SyncEngine({
    required this.onSyncStarted,
    required this.onSyncComplete,
    required this.onStateUpdated,
    this.onTransientOffline,
    String logTag = 'sync',
    WalletStore? walletRepository,
    SettingsStore? settingsRepository,
    FrigateTipProbeFn? frigateProbe,
    WatchedOutputsFn? watchedOutputsFn,
    FrigateScanFn? frigateScanFn,
    FrigateMonitorStartFn? frigateMonitorStart,
    FrigateMonitorStopFn? frigateMonitorStop,
    FrigateMonitorActiveFn? frigateMonitorActive,
    this.monitorBeatInterval = const Duration(seconds: 30),
    ChainHeightFn? chainHeightFn,
    NetworkCheckFn? networkCheckFn,
    SyncResultStreamFn? resultStreamFn,
  })  : walletRepository = walletRepository ?? WalletRepository.instance,
        settingsRepository = settingsRepository ?? SettingsRepository.instance,
        frigateProbe = frigateProbe ?? _defaultFrigateProbe,
        watchedOutputsFn = watchedOutputsFn ?? _defaultWatchedOutputs,
        frigateScanFn = frigateScanFn ?? _defaultFrigateScan,
        frigateMonitorStart =
            frigateMonitorStart ?? _defaultFrigateMonitorStart,
        frigateMonitorStop = frigateMonitorStop ?? _defaultFrigateMonitorStop,
        frigateMonitorActive =
            frigateMonitorActive ?? _defaultFrigateMonitorActive,
        chainHeightFn = chainHeightFn ?? getChainHeight,
        networkCheckFn = networkCheckFn ?? checkNetwork,
        syncResultStreamFn = resultStreamFn ?? createSyncResultStream,
        _logTag = logTag {
    _syncResultSubscription = syncResultStreamFn().listen(_onSyncResult);
  }

  static Future<FrigateTipProbe> _defaultFrigateProbe({required String url}) =>
      frigateTipProbe(url: url);

  static Future<List<WatchedOutput>> _defaultWatchedOutputs() =>
      OwnedOutputsRepository.instance.getWatchedOutputs();

  static Future<FrigateScanOutcome> _defaultFrigateScan({
    required String frigateUrl,
    required int fromHeight,
    required BigInt dustLimit,
    required List<WatchedOutput> watchedOutputs,
  }) async {
    final wallet = await WalletRepository.instance.readWallet();
    return wallet!.syncViaFrigate(
        frigateUrl: frigateUrl,
        fromHeight: fromHeight,
        dustLimit: dustLimit,
        watchedOutputs: watchedOutputs);
  }

  static Future<void> _defaultFrigateMonitorStart({
    required String frigateUrl,
    required int fromHeight,
    required BigInt dustLimit,
    required List<WatchedOutput> watchedOutputs,
  }) async {
    final wallet = await WalletRepository.instance.readWallet();
    await wallet!.startFrigateMonitor(
        frigateUrl: frigateUrl,
        fromHeight: fromHeight,
        dustLimit: dustLimit,
        watchedOutputs: watchedOutputs);
  }

  static Future<void> _defaultFrigateMonitorStop() async {
    frigate_api.stopFrigateMonitor();
  }

  static Future<bool> _defaultFrigateMonitorActive() async {
    return frigate_api.frigateMonitorRunning();
  }

  // Only used by _onSyncResult (not exercised in the wake acceptance tests;
  // singletons are fine here since no rust call is involved).
  final _ownedOutputsRepository = OwnedOutputsRepository.instance;
  final _transactionsRepository = TransactionsRepository.instance;

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

    await walletRepository.saveLastSync(event.blkheight);

    // keep the scan-session heartbeat fresh while a frigate scan is running
    if (_frigateScanRunning) {
      await walletRepository.touchFrigateScanBeat();
    }

    if (event.foundOutputs.isNotEmpty || event.foundInputs.isNotEmpty) {
      await onStateUpdated(false);
    } else {
      await onStateUpdated(true);
    }
  }

  /// Phase-2/3 wiring: keep a continuous frigate subscription (the
  /// [FrigateMonitor]) alive while the foreground service runs.
  ///
  /// The monitor delivers the phase-2 mempool tail over the key-bearing
  /// subscription (decision-record amendment 2026-11-10); the wake-cycle
  /// one-shot stays the phase-1 catch-up. Liveness reuses the persisted
  /// scan-session state (D2/D3): the monitor holds the session keys (single
  /// writer), keeps the beat fresh, and the rust-side task state is the
  /// cross-isolate truth — a dead task is restarted from the checkpoint, so
  /// no receipt is ever lost to monitor downtime (its history sweep
  /// re-discovers anything missed, and confirmed outpoints are idempotent).
  Future<void> ensureFrigateMonitor() async {
    if (!await walletRepository.hasWallet()) {
      return;
    }

    final url = (await settingsRepository.getFrigateUrl())?.trim();
    final backend = await settingsRepository.getFrigateBackend();
    final wantMonitor =
        backend == frigateBackendFrigate && url != null && url.isNotEmpty;

    // D9: a monitor must never outlive its backend selection.
    if (!wantMonitor) {
      if (_frigateMonitorRunning) {
        Logger().i('[$_logTag] backend left frigate, stopping monitor');
        await stopFrigateMonitor();
      }
      return;
    }

    if (_frigateMonitorRunning) {
      if (await frigateMonitorActive()) {
        // held subscription: keep the session beat fresh, do nothing else
        await walletRepository.touchFrigateScanBeat();
        return;
      }
      Logger().w('[$_logTag] frigate monitor task died, restarting');
      _frigateMonitorRunning = false;
    }

    // The monitor needs an initialized checkpoint; the wake one-shot
    // initializes it from the birthday height first.
    final lastSync = await walletRepository.readLastSync();
    if (lastSync == null) {
      Logger().i('[$_logTag] frigate monitor deferred: checkpoint not '
          'initialized yet');
      return;
    }

    final dustLimit =
        await settingsRepository.getDustLimit() ?? defaultDustLimit;

    // Single-writer (D2): the monitor isolate owns the session keys while it
    // holds the subscription.
    await walletRepository.beginFrigateScan(pid: pid);
    _frigateScanRunning = true;
    try {
      // A monitor start is a subscribe (D7): append the disclosure record.
      final visibility = await settingsRepository.getFrigateVisibility() ??
          frigateVisibilityPrivate;
      await walletRepository.appendFrigateDisclosureRecord(
          url: url, visibility: visibility);

      final watchedOutputs = await watchedOutputsFn();

      await frigateMonitorStart(
          frigateUrl: url,
          fromHeight: lastSync + 1,
          dustLimit: BigInt.from(dustLimit),
          watchedOutputs: watchedOutputs);

      _frigateMonitorRunning = true;
      _startMonitorBeat();
      Logger().i('[$_logTag] frigate monitor running from ${lastSync + 1}');
    } catch (e) {
      await walletRepository.endFrigateScan();
      _frigateScanRunning = false;
      Logger().w('[$_logTag] frigate monitor failed to start: $e');
    }
  }

  /// Drop the monitor subscription cleanly: abort the scanner task and clear
  /// the persisted scan-session state.
  Future<void> stopFrigateMonitor() async {
    _monitorBeatTimer?.cancel();
    _monitorBeatTimer = null;
    if (!_frigateMonitorRunning) {
      return;
    }
    try {
      await frigateMonitorStop();
    } finally {
      _frigateMonitorRunning = false;
      _frigateScanRunning = false;
      await walletRepository.endFrigateScan();
    }
  }

  /// Keeps the persisted scan-session heartbeat fresh while the monitor
  /// holds the subscription (liveness marker for a killed process, D2).
  void _startMonitorBeat() {
    final interval = monitorBeatInterval;
    if (interval == null) {
      return;
    }
    _monitorBeatTimer?.cancel();
    _monitorBeatTimer = Timer.periodic(interval, (_) {
      unawaited(walletRepository.touchFrigateScanBeat());
    });
  }

  Future<void> trySync() async {
    if (_isSyncing) {
      Logger().i('[$_logTag] sync already in progress, skipping');
      return;
    }
    _isSyncing = true;
    try {
      if (!await walletRepository.hasWallet()) {
        Logger().i('[$_logTag] no wallet, skipping');
        return;
      }

      final network = await walletRepository.readNetwork();
      final blindbitUrl = await settingsRepository.getBlindbitUrl() ??
          network.defaultBlindbitUrl;

      // Explicit backend selection (D9): the frigate backend runs only when
      // the user picked it AND a URL is configured. An unset backend or an
      // unset/empty URL keeps the blindbit path byte-identical (blindbit
      // stays the default).
      final frigateUrl = (await settingsRepository.getFrigateUrl())?.trim();
      final backend = await settingsRepository.getFrigateBackend();
      final useFrigate = backend == frigateBackendFrigate &&
          frigateUrl != null &&
          frigateUrl.isNotEmpty;
      if (backend == frigateBackendFrigate && !useFrigate) {
        Logger().w('[$_logTag] frigate backend selected but no url '
            'configured, falling back to blindbit');
      }

      int? tip;
      String? probeTipHash;
      if (useFrigate) {
        // The monitor covers the live tail while it holds the subscription
        // (phase 2): the wake one-shot must not re-subscribe on top of it
        // (D3: no duplicate subscription, no wake-cycle re-disclosure). A
        // dead monitor is restarted by the service's liveness pass, and the
        // phase-1 recovery path below runs whenever no monitor is live.
        if (_frigateMonitorRunning) {
          Logger().i('[$_logTag] frigate monitor live, wake scan skipped');
          await walletRepository.touchFrigateScanBeat();
          return;
        }

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
          final probe = await frigateProbe(url: frigateUrl);
          tip = probe.tipHeight;
          probeTipHash = probe.tipHash;
        } catch (e) {
          Logger().w('[$_logTag] frigate unreachable: $e');
          onTransientOffline?.call(frigateOfflineMsg);
          return;
        }
      } else {
        final correctNetwork =
            await networkCheckFn(blindbitUrl: blindbitUrl, network: network);
        if (!correctNetwork) {
          Logger().w('[$_logTag] wrong network, skipping');
          return;
        }

        tip = await chainHeightFn(blindbitUrl: blindbitUrl);
      }

      var lastSync = await walletRepository.readLastSync();

      if (lastSync == null) {
        lastSync = await _heightFromBirthday(network);
        await walletRepository.saveLastSync(lastSync);
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

      Logger().i('[$_logTag] syncing $lastSync -> $tip');

      final dustLimit =
          await settingsRepository.getDustLimit() ?? defaultDustLimit;

      // The probe/getChainHeight tip gives the bar a real end height up
      // front, so it can become determinate as soon as scanner Heights
      // arrive (D4).
      onSyncStarted(lastSync + 1, tip);

      if (useFrigate) {
        // Single-writer (D2): only this isolate, which runs the scan, writes
        // the session keys.
        await walletRepository.beginFrigateScan(pid: pid);
        _frigateScanRunning = true;
        try {
          // D7 disclosure record: every subscribe appends {url, visibility,
          // date} to the wallet's append-only record list. The list never
          // drives a dialog; visibility defaults to private (D5).
          final visibility = await settingsRepository.getFrigateVisibility() ??
              frigateVisibilityPrivate;
          await walletRepository.appendFrigateDisclosureRecord(
              url: frigateUrl, visibility: visibility);

          // Watched outputs carry script bytes so the scanner re-subscribes
          // them on start: unspent + unconfirmed-spent outputs, mirroring the
          // blindbit scan list. This is the single disclosure point —
          // reached only when a scan will actually run (D3).
          final watchedOutputs = await watchedOutputsFn();

          final outcome = await frigateScanFn(
              frigateUrl: frigateUrl,
              fromHeight: lastSync + 1,
              dustLimit: BigInt.from(dustLimit),
              watchedOutputs: watchedOutputs);

          // Persist the last tip pair (diagnostics + the D9 boundary record;
          // never drives the checkpoint) and clear the lock whatever the
          // outcome was.
          await walletRepository.endFrigateScan(
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
          await walletRepository.endFrigateScan(
              tipHeight: tip, tipHash: probeTipHash);
          rethrow;
        } finally {
          _frigateScanRunning = false;
        }
      } else {
        final wallet = await walletRepository.readWallet();
        if (wallet == null) {
          Logger().w('[$_logTag] wallet vanished mid-wake, skipping');
          return;
        }
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
    final lock = await walletRepository.readFrigateScanLock();
    if (lock == null) return;
    Logger().w('[$_logTag] clearing stale frigate scan lock '
        '(pid=${lock.pid}, stale=${lock.isStale(currentPid: pid)})');
    await walletRepository.endFrigateScan();
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
    final birthday = await walletRepository.readBirthday() ?? defaultBirthday;
    final mempoolApi = MempoolApiRepository(network: network);
    final block = await mempoolApi.getBlockFromTimestamp(birthday.toSeconds());
    return block.height;
  }

  void dispose() {
    _monitorBeatTimer?.cancel();
    _syncResultSubscription.cancel();
  }
}
