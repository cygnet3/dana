import 'dart:async';
import 'dart:io';

import 'package:danawallet/constants.dart';
import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class SyncProgressNotifier extends ChangeNotifier {
  Completer? _completer;
  double? progress;
  int? startHeight;
  int? endHeight;

  late StreamSubscription syncProgressSubscription;

  bool get isScanning => _completer != null && !_completer!.isCompleted;

  // private constructor
  SyncProgressNotifier._();

  Future<void> _initialize() async {
    syncProgressSubscription = createSyncProgressStream().listen((current) {
      // Only update progress while the bar is active. Ignoring events outside
      // of an active scan prevents a trailing Rust event from re-activating the
      // bar after deactivate() has already been called.
      if (!isScanning) return;

      final start = startHeight;
      final end = endHeight;
      if (start == null || end == null || end <= start) return;

      final progress = (current - start) / (end - start);
      if (current != end) {
        this.progress = progress;
        notifyListeners();
      }
    });
  }

  static Future<SyncProgressNotifier> create() async {
    final instance = SyncProgressNotifier._();
    await instance._initialize();
    return instance;
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      FlutterForegroundTask.removeTaskDataCallback(onServiceData);
    }
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

  /// Called by the main isolate's service data callback with messages from
  /// the background sync task.
  void onServiceData(Object data) {
    if (data is! Map) return;
    if (data.containsKey(bgKeyStartHeight) &&
        data.containsKey(bgKeyEndHeight)) {
      startHeight = (data[bgKeyStartHeight] as num).toInt();
      endHeight = (data[bgKeyEndHeight] as num).toInt();
      activate();
    } else if (data.containsKey(bgKeyComplete)) {
      deactivate();
    }
  }

  /// Waits for an active scan to complete or be interrupted, then returns.
  /// Does not signal the interrupt itself — callers are responsible for doing
  /// so through the appropriate channel (in-process or IPC).
  Future<void> waitForCompletion() async {
    if (!isScanning) return;
    await _completer?.future.timeout(
      const Duration(seconds: 10),
      onTimeout: deactivate,
    );
  }

  /// Signals an in-process scan to stop and waits for it to finish.
  /// Only correct to call when sync is running in the same Dart isolate.
  Future<void> interruptSync() async {
    if (!isScanning) return;
    SpWallet.interruptSync();
    await waitForCompletion();
  }
}
