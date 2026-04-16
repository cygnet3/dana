/// The result of [SyncBackend.start], used by [SyncOrchestrator] to update
/// its UI-visible state without knowing platform details.
enum SyncStartResult { started, fallback }

/// UI prompts that [AndroidSyncBackend] may need the app layer to display.
/// Only relevant on Android; the enum lives here so callers can import a single
/// file rather than reaching into the orchestrator.
enum SyncAppAction {
  /// Notification permission has not been granted; warn the user that
  /// background sync will not work without it.
  notificationPermissionWarning,
}
