import 'package:danawallet/services/sync_task_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logger/logger.dart';

class ForegroundSyncService {
  ForegroundSyncService._();
  static final instance = ForegroundSyncService._();

  static const String _notificationChannelId = 'dana_sync';
  static const String _notificationChannelName = 'Dana background sync';
  static const String _notificationChannelDescription =
      'Keeps your wallet up to date in the background';
  static const String _foregroundNotificationTitle = 'Dana wallet';
  static const String _foregroundNotificationText =
      'Keeping your wallet up to date';

  /// Call once at app startup, before runApp().
  void initialize() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _notificationChannelId,
        channelName: _notificationChannelName,
        channelDescription: _notificationChannelDescription,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: synchronizationTaskOptions,
    );
  }

  /// Start the foreground service. Safe to call even if already running.
  /// Does not block startup — await this fire-and-forget with unawaited().
  Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      Logger().i('Android foreground service already running');
      return;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 1000,
      notificationTitle: _foregroundNotificationTitle,
      notificationText: _foregroundNotificationText,
      callback: startCallback,
    );

    if (result is ServiceRequestSuccess) {
      Logger().i('Android foreground service started');
    } else if (result is ServiceRequestFailure) {
      Logger().w(
        'Failed to start Android foreground service: ${result.error}',
      );
    }
  }

  Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
    Logger().i('Android foreground service stopped');
  }
}
