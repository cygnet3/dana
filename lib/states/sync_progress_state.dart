import 'dart:async';

import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:flutter/material.dart';

class SyncProgressState extends ChangeNotifier {
  bool isSyncing = false;
  Completer? _completer;
  double? progress;
  int? _startHeight;
  int? _endHeight;

  late StreamSubscription syncProgressSubscription;

  // private constructor
  SyncProgressState._();

  void _initialize() {
    syncProgressSubscription = createSyncProgressStream().listen((current) {
      // Only update progress while the bar is active. Ignoring events outside
      // of an active scan prevents a trailing Rust event from re-activating the
      // bar after deactivate() has already been called.
      if (!isSyncing) return;

      final start = _startHeight;
      final end = _endHeight;
      if (start == null || end == null || end <= start) return;

      final progress = (current - start) / (end - start);
      if (current != end) {
        this.progress = progress;
        notifyListeners();
      }
    });
  }

  static Future<SyncProgressState> create() async {
    final instance = SyncProgressState._();
    instance._initialize();
    return instance;
  }

  @override
  void dispose() {
    syncProgressSubscription.cancel();
    super.dispose();
  }

  void activate(int startHeight, int endHeight) {
    // if a start height has already been set, we ignore the start height variable
    // this is because we might be continuing from a previous sync progress sync point,
    // which got interrupted by an error
    _startHeight ??= startHeight;
    _endHeight = endHeight;

    isSyncing = true;

    _completer = Completer();
    progress = null;
    notifyListeners();
  }

  void deactivate(bool clear) {
    isSyncing = false;
    progress = null;
    _completer?.complete();

    if (clear) {
      _startHeight = null;
    }
    notifyListeners();
  }

  /// Waits for an active scan to complete or be interrupted, then returns.
  /// Does not signal the interrupt itself — callers are responsible for doing
  /// so through the appropriate channel (in-process or IPC).
  Future<void> waitForCompletion() async {
    if (!isSyncing) return;
    await _completer?.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => deactivate(true),
    );
  }

  /// Signals an in-process scan to stop and waits for it to finish.
  /// Only correct to call when sync is running in the same Dart isolate.
  Future<void> interruptSync() async {
    if (!isSyncing) return;
    SpWallet.interruptSync();
    await waitForCompletion();
  }
}
