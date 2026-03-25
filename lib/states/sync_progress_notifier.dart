import 'dart:async';

import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/structs/sync_queue_item.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';

class SyncProgressNotifier extends ChangeNotifier {
  Completer? _completer;
  double? progress;
  late SyncQueueItem item;
  late int totalToSync;
  late int synced;

  late StreamSubscription syncProgressSubscription;

  bool get isScanning => _completer != null && !_completer!.isCompleted;

  // private constructor
  SyncProgressNotifier._();

  Future<void> _initialize() async {
    syncProgressSubscription = createSyncProgressStream().listen(((current) {
      synced++;
      if (synced != totalToSync) {
        progress = (synced.toDouble() / totalToSync.toDouble());
        notifyListeners();
      }
    }));
  }

  static Future<SyncProgressNotifier> create() async {
    final instance = SyncProgressNotifier._();
    await instance._initialize();
    return instance;
  }

  @override
  void dispose() {
    syncProgressSubscription.cancel();
    super.dispose();
  }

  void activate() {
    _completer = Completer();
    progress = null;
    notifyListeners();
  }

  void deactivate() {
    _completer?.complete();
    progress = null;
    notifyListeners();
  }

  Future<void> scan(WalletState walletState, SyncQueueItem item, int synced,
      int totalToSync) async {
    this.synced = synced;
    this.totalToSync = totalToSync;

    try {
      final wallet = await walletState.getWalletFromSecureStorage();
      final settings = SettingsRepository.instance;
      final blindbitUrl = await settings.getBlindbitUrl() ??
          walletState.network.defaultBlindbitUrl;
      final dustLimit = await settings.getDustLimit() ?? defaultDustLimit;

      if (walletState.lastSync == null) {
        throw Exception("Last scan is null");
      }

      final ownedOutPoints =
          walletState.ownedOutputs.getUnconfirmedSpentOutpoints();

      activate();
      await wallet.syncToHeight(
        item: item,
        blindbitUrl: blindbitUrl,
        dustLimit: BigInt.from(dustLimit),
        ownedOutpoints: ownedOutPoints,
      );
    } catch (e) {
      deactivate();
      rethrow;
    }
    deactivate();
  }

  void reset() {
    synced = 0;
  }

  Future<void> interruptSync() async {
    if (isScanning) {
      SpWallet.interruptSync();

      // this makes sure the scan function has been terminated
      await _completer?.future;
    }
  }
}
