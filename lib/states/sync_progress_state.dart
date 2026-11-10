import 'dart:async';

import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/structs/sync_progress_event.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:flutter/material.dart';

/// Tracks sync progress for the UI progress bar.
///
/// Events are tagged [SyncProgressEvent]s: a frigate scan announces the chain
/// tip first (the determinate bar's end height, superseded by later scanner
/// tips on reorg), then the pump reports scanner heights. Progress stays
/// null — indeterminate — until both the tip-driven end and a first scanner
/// Height have arrived; it is never interpolated (D4).
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
    syncProgressSubscription = createSyncProgressStream().listen((event) {
      // Only update progress while the bar is active. Ignoring events outside
      // of an active scan prevents a trailing Rust event from re-activating the
      // bar after deactivate() has already been called.
      if (!isSyncing) return;

      switch (event) {
        case SyncProgressEvent_Tip(:final height):
          // Scanner tip supersedes the wake-time probe tip (possible reorg
          // between probe and scan): the bar's end follows the scanner.
          _endHeight = height;
        case SyncProgressEvent_Height(:final field0):
          _onScannerHeight(field0);
      }
      notifyListeners();
    });
  }

  void _onScannerHeight(int current) {
    final start = _startHeight;
    final end = _endHeight;
    // Indeterminate until both the tip-driven end and a scanner Height have
    // arrived (a degenerate end <= start also stays indeterminate).
    if (start == null || end == null || end <= start) return;

    // The final height is handled by deactivate() on sync completion.
    if (current < end) {
      progress = (current - start) / (end - start);
    }
  }

  static SyncProgressState create() {
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
