import 'dart:async';

import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/extensions/outpoint.dart';
import 'package:danawallet/generated/rust/api/chain.dart';
import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/structs/outpoint.dart';
import 'package:danawallet/generated/rust/api/structs/state_update.dart';
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

  final String _logTag;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;
  Completer<void>? _idleCompleter;

  late final StreamSubscription _syncResultSubscription;

  final _ownedOutputsRepository = OwnedOutputsRepository.instance;
  final _transactionsRepository = TransactionsRepository.instance;
  final _walletRepository = WalletRepository.instance;

  SyncEngine({
    required this.onSyncStarted,
    required this.onSyncComplete,
    required this.onStateUpdated,
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

      // In frigate mode the scanner streams until CaughtUp, so the blindbit
      // chain-height precheck (network check + tip lookup) is skipped.
      int? tip;
      if (!useFrigate) {
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

      if (tip != null && lastSync >= tip) {
        Logger().i('[$_logTag] up to date (lastSync=$lastSync tip=$tip)');
        return;
      }

      Logger()
          .i('[$_logTag] syncing $lastSync -> ${tip ?? "frigate caught-up"}');

      final dustLimit = await settings.getDustLimit() ?? defaultDustLimit;

      // In frigate mode the caught-up tip is unknown up front, so the bar is
      // activated with end == start and stays indeterminate.
      onSyncStarted(lastSync + 1, tip ?? lastSync + 1);

      if (useFrigate) {
        // Watched outputs carry script bytes so the scanner re-subscribes
        // them on start: unspent + unconfirmed-spent outputs, mirroring the
        // blindbit scan list.
        final watchedOutputs =
            await _ownedOutputsRepository.getWatchedOutputs();

        await wallet.syncViaFrigate(
            frigateUrl: frigateUrl,
            fromHeight: lastSync + 1,
            dustLimit: BigInt.from(dustLimit),
            watchedOutputs: watchedOutputs);
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
            toHeight: tip!,
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
