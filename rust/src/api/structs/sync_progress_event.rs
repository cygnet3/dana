use flutter_rust_bridge::frb;

/// Element type of the shared sync-progress stream (`stream.rs`).
///
/// One channel carries both blindbit scan positions and frigate tip
/// announcements; Dart distinguishes them by variant instead of treating
/// every height as "current scan position".
#[derive(Debug, Clone)]
#[frb]
pub enum SyncProgressEvent {
    /// Current scan position reported by the sync pump (blindbit and
    /// frigate scanner progress alike). Purely informational for the UI.
    Height(u32),
    /// Chain tip announced by the frigate server — always the first event
    /// of a frigate scan. Dart uses it as the determinate bar's end height;
    /// it never reaches the checkpoint (only confirmed pump updates do).
    Tip { height: u32 },
}
