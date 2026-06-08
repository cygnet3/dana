import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart'
    as permission_handler;

/// Tracks background-sync related permissions/capabilities for UI and backend.
/// TODO we don't handle the battery optimization permission but it can influence
/// operation of the foreground service
class PermissionState extends ChangeNotifier {
  bool _notificationGranted = false;
  DateTime? _lastCheckedAt;

  bool get notificationGranted => _notificationGranted;
  DateTime? get lastCheckedAt => _lastCheckedAt;

  static Future<PermissionState> create() async {
    final state = PermissionState();
    await state.refresh();
    return state;
  }

  Future<void> refresh() async {
    final nextNotificationGranted = Platform.isAndroid
        ? await FlutterForegroundTask.checkNotificationPermission() ==
            NotificationPermission.granted
        : true;
    _setState(
      notificationGranted: nextNotificationGranted,
    );
  }

  Future<void> requestBackgroundSyncPermissions() async {
    if (!Platform.isAndroid) return;

    await FlutterForegroundTask.requestNotificationPermission();
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    await refresh();
  }

  /// Requests permissions and, if needed, opens system settings, waits until
  /// the app is resumed, then re-checks permissions.
  Future<bool> requestPermissionsAndWaitForSettingsReturn() async {
    if (!Platform.isAndroid) return true;

    await FlutterForegroundTask.requestNotificationPermission();
    await refresh();
    if (_notificationGranted) return true;

    final opened = await permission_handler.openAppSettings();
    if (!opened) return false;

    await _waitForAppResume();
    await refresh();
    return _notificationGranted;
  }

  Future<void> _waitForAppResume({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == AppLifecycleState.resumed) return;

    final completer = Completer<void>();
    final observer = _ResumeLifecycleObserver(onResumed: () {
      if (!completer.isCompleted) completer.complete();
    });
    WidgetsBinding.instance.addObserver(observer);
    try {
      await completer.future.timeout(timeout, onTimeout: () {});
    } finally {
      WidgetsBinding.instance.removeObserver(observer);
    }
  }

  void _setState({
    required bool notificationGranted,
  }) {
    final changed = _notificationGranted != notificationGranted;
    _notificationGranted = notificationGranted;
    _lastCheckedAt = DateTime.now();
    if (changed) notifyListeners();
  }
}

class _ResumeLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResumed;

  _ResumeLifecycleObserver({required this.onResumed});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}
