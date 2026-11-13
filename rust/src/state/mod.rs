mod updater;

pub use updater::SyncUpdatePump;

#[cfg(test)]
pub use updater::RecordingSink;
