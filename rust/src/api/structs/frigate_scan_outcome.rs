use flutter_rust_bridge::frb;

/// Typed outcome of a one-shot frigate scan (`sync_via_frigate`).
///
/// A `Disconnected` outcome is a normal result, not an error: the checkpoint
/// has already advanced to the last confirmed block the pump emitted, so the
/// next wake simply resumes from there (D8: no red error, no blindbit
/// fallback).
#[derive(Debug, Clone)]
#[frb]
pub enum FrigateScanOutcome {
    /// Server reported `CaughtUp`; the checkpoint was finalized at the tip.
    Completed,
    /// Scan ended before `CaughtUp`: connection death, silent channel close,
    /// or user interrupt via the existing `interruptSync` path. `reason` is
    /// a human-readable cause for the log/banner.
    Disconnected { reason: String },
}
