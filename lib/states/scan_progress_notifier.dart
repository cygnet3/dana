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
  late int start;
  late int end;

  late StreamSubscription scanProgressSubscription;

  bool get scanning => _completer != null && !_completer!.isCompleted;

  // private constructor
  ScanProgressNotifier._();

  Future<void> _initialize() async {
    scanProgressSubscription = createScanProgressStream().listen(((current) {
      double scanned = (current - start).toDouble();
      double total = (end - start).toDouble();
      double progress = scanned / total;
      if (current != end) {
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

  Future<void> scan(WalletState walletState, int start, int end) async {
    this.start = start;
    this.end = end;

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
      await wallet.scanToTip(
          blindbitUrl: blindbitUrl,
          dustLimit: BigInt.from(dustLimit),
          ownedOutpoints: ownedOutPoints,
          lastScan: walletState.lastScan!);
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
