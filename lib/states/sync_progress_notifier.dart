import 'dart:async';

import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:flutter/material.dart';

class SyncProgressState extends ChangeNotifier {
  bool isSyncing = false;
  double? progress;
  int? _fromHeight;
  late int _toHeight;

  late StreamSubscription syncProgressSubscription;

  // private constructor
  SyncProgressState._();

  Future<void> _initialize() async {
    syncProgressSubscription = createSyncProgressStream().listen(((current) {
      double scanned = (current - _fromHeight!).toDouble();
      double total = (_toHeight - _fromHeight!).toDouble();
      double progress = scanned / total;
      if (current != _toHeight) {
        this.progress = progress;

        notifyListeners();
      }
    }));
  }

  static Future<SyncProgressState> create() async {
    final instance = SyncProgressState._();
    await instance._initialize();
    return instance;
  }

  @override
  void dispose() {
    syncProgressSubscription.cancel();
    super.dispose();
  }

  Future<void> activate(int fromHeight, int toHeight) async {
    // if a start height has already been set, we ignore the start height variable
    // this is because we might be continuing from a previous sync progress sync point,
    // which got interrupted by an error
    _fromHeight ??= fromHeight;
    // we always set the end height
    _toHeight = toHeight;

    isSyncing = true;
    progress = null;
    notifyListeners();
  }

  void deactivate(bool clear) {
    isSyncing = false;
    progress = null;
    if (clear) {
      _fromHeight = null;
    }

    notifyListeners();
  }
}
