use crate::api::structs::state_update::StateUpdate;
use crate::logger::{LogEntry, LogLevel};
use crate::{frb_generated::StreamSink, stream};

#[flutter_rust_bridge::frb(sync)]
pub fn create_log_stream(s: StreamSink<LogEntry>, level: LogLevel, log_dependencies: bool) {
    crate::logger::init_logger(level.into(), log_dependencies);
    crate::logger::FlutterLogger::set_stream_sink(s);
}

#[flutter_rust_bridge::frb(sync)]
pub fn create_sync_progress_stream(s: StreamSink<u32>) {
    stream::create_sync_progress_stream(s);
}

#[flutter_rust_bridge::frb(sync)]
pub fn create_sync_result_stream(s: StreamSink<StateUpdate>) {
    stream::create_sync_update_stream(s);
}
