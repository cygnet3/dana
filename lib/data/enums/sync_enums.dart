/// The result of [SyncBackend.start], used by [SyncOrchestrator] to update
/// its UI-visible state without knowing platform details.
enum SyncStartResult { foreground, fallback, inProcess }
