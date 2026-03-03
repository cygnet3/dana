import 'dart:async';

import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';

class ScanProgressNotifier extends ChangeNotifier {
  Completer? _completer;
  double progress = 0.0;
  late int startHeight;
  late int endHeight;

  late StreamSubscription scanProgressSubscription;

  bool get scanning => _completer != null && !_completer!.isCompleted;

  // private constructor
  ScanProgressNotifier._();

  Future<void> _initialize() async {
    scanProgressSubscription = createScanProgressStream().listen(((current) {
      double scanned = (current - startHeight).toDouble();
      double total = (endHeight - startHeight).toDouble();
      double progress = scanned / total;
      if (current != endHeight) {
        this.progress = progress;

        notifyListeners();
      }
    }));
  }

  static Future<ScanProgressNotifier> create() async {
    final instance = ScanProgressNotifier._();
    await instance._initialize();
    return instance;
  }

  @override
  void dispose() {
    scanProgressSubscription.cancel();
    super.dispose();
  }

  void activate() {
    _completer = Completer();
    progress = 0.0;
    notifyListeners();
  }

  void deactivate() {
    _completer?.complete();
    progress = 0.0;
    notifyListeners();
  }

  Future<void> scan(WalletState walletState, int startHeight, int chainTip) async {
    this.startHeight = startHeight;
    endHeight = chainTip;

    // start syncing from the first block after our last sync
    // we ignore the startHeight here, because we may be continuing from another sync
    final fromHeight = walletState.lastScan! + 1;
    final toHeight = chainTip;

    try {
      final wallet = await walletState.getWalletFromSecureStorage();
      final settings = SettingsRepository.instance;
      final blindbitUrl = await settings.getBlindbitUrl() ??
          walletState.network.defaultBlindbitUrl;
      final dustLimit = await settings.getDustLimit() ?? defaultDustLimit;

      if (walletState.lastScan == null) {
        throw Exception("Last scan is null");
      }

      final ownedOutPoints =
          walletState.ownedOutputs.getUnconfirmedSpentOutpoints();

      activate();
      await wallet.syncToHeight(
        fromHeight: fromHeight,
        toHeight: toHeight,
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

  Future<void> interruptScan() async {
    if (scanning) {
      SpWallet.interruptScanning();

      // this makes sure the scan function has been terminated
      await _completer?.future;
    }
  }
}
