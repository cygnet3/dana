use std::{
    sync::{Once, RwLock},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use crate::frb_generated::StreamSink;
use log::{warn, LevelFilter, Log, Metadata, Record};

use lazy_static::lazy_static;
use simplelog::{CombinedLogger, Config, SharedLogger};

lazy_static! {
    static ref FLUTTER_LOGGER_STREAM_SINK: RwLock<Option<StreamSink<LogEntry>>> = RwLock::new(None);
}

static INIT_LOGGER_ONCE: Once = Once::new();

#[derive(Debug)]
pub struct LogEntry {
    pub time_millis: i64,
    pub level: String,
    pub tag: String,
    pub msg: String,
}

pub fn init_logger(level: LevelFilter, show_dependency_logs: bool) {
    INIT_LOGGER_ONCE.call_once(|| {
        CombinedLogger::init(vec![
            Box::new(FlutterLogger::new(level, show_dependency_logs)),
            // todo add more loggers
        ])
        .unwrap();
    });
}

pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
    Off,
}

impl From<LogLevel> for LevelFilter {
    fn from(value: LogLevel) -> Self {
        match value {
            LogLevel::Debug => LevelFilter::Debug,
            LogLevel::Info => LevelFilter::Info,
            LogLevel::Warn => LevelFilter::Warn,
            LogLevel::Error => LevelFilter::Error,
            LogLevel::Off => LevelFilter::Off,
        }
    }
}

pub struct FlutterLogger {
    level: LevelFilter,
    log_dependencies: bool,
}

impl FlutterLogger {
    pub fn set_stream_sink(stream_sink: StreamSink<LogEntry>) {
        // unwrap_or_else: recover from a poisoned lock.  The foreground service
        // can keep the process alive across builds, so a panic from an old
        // binary version that held this lock may still be present.
        let mut guard = FLUTTER_LOGGER_STREAM_SINK
            .write()
            .unwrap_or_else(|e| e.into_inner());
        let overriding = guard.is_some();

        *guard = Some(stream_sink);

        drop(guard);

        if overriding {
            warn!(
                "FlutterLogger::set_stream_sink but already exist a sink, thus overriding. \
                (This may or may not be a problem. It will happen normally if hot-reload Flutter app.)"
            );
        }
    }

    pub fn new(level: LevelFilter, log_dependencies: bool) -> Self {
        FlutterLogger {
            level,
            log_dependencies,
        }
    }

    fn record_to_entry(record: &Record) -> LogEntry {
        let time_millis = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_else(|_| Duration::from_secs(0))
            .as_millis() as i64;

        let level = record.level().to_string();

        let tag = record.target().to_owned();

        let msg = format!("{}", record.args());

        LogEntry {
            time_millis,
            level,
            tag,
            msg,
        }
    }
}

impl Log for FlutterLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        if metadata.target().starts_with("sp_backend") {
            true
        } else {
            self.log_dependencies
        }
    }

    fn log(&self, record: &Record) {
        if self.enabled(record.metadata()) {
            let entry = Self::record_to_entry(record);
            // try_read instead of read:
            //   • Never blocks — a log call can never delay set_stream_sink().
            //     The only writer is set_stream_sink() which runs briefly and
            //     infrequently; with try_read() no readers queue behind a
            //     pending writer, so writer starvation is impossible.
            //   • Never panics — try_read() returns Err on a poisoned lock
            //     rather than panicking, and the if-let simply skips the
            //     message.  A missed log line during the lock handover is an
            //     acceptable trade-off.
            if let Ok(guard) = FLUTTER_LOGGER_STREAM_SINK.try_read() {
                if let Some(sink) = &*guard {
                    let _ = sink.add(entry);
                }
            }
        }
    }

    fn flush(&self) {
        // no need
    }
}

impl SharedLogger for FlutterLogger {
    fn level(&self) -> LevelFilter {
        self.level
    }

    fn config(&self) -> Option<&Config> {
        None
    }

    fn as_log(self: Box<Self>) -> Box<dyn Log> {
        Box::new(*self)
    }
}
