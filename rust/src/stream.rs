use std::{
    collections::{HashMap, HashSet},
    sync::Mutex,
};

use crate::frb_generated::StreamSink;
use lazy_static::lazy_static;
use spdk_wallet::{
    bitcoin::{absolute::Height, BlockHash, OutPoint},
    updater::SimplifiedOutput,
};

lazy_static! {
    static ref SCAN_PROGRESS_STREAM_SINK: Mutex<Option<StreamSink<ScanProgress>>> =
        Mutex::new(None);
    static ref STATE_UPDATE_STREAM_SINK: Mutex<Option<StreamSink<StateUpdate>>> = Mutex::new(None);
}

#[derive(Debug)]
pub enum StateUpdate {
    NoUpdate {
        blkheight: Height,
    },
    Update {
        blkheight: Height,
        blkhash: BlockHash,
        found_outputs: HashMap<OutPoint, SimplifiedOutput>,
        found_inputs: HashSet<OutPoint>,
    },
}

pub struct ScanProgress {
    pub start: u32,
    pub current: u32,
    pub end: u32,
}

pub fn create_scan_progress_stream(s: StreamSink<ScanProgress>) {
    let mut stream_sink = SCAN_PROGRESS_STREAM_SINK.lock().unwrap();
    *stream_sink = Some(s);
}

pub fn create_scan_update_stream(s: StreamSink<StateUpdate>) {
    let mut stream_sink = STATE_UPDATE_STREAM_SINK.lock().unwrap();
    *stream_sink = Some(s);
}

pub(crate) fn send_scan_progress(scan_progress: ScanProgress) {
    let stream_sink = SCAN_PROGRESS_STREAM_SINK.lock().unwrap();
    if let Some(stream_sink) = stream_sink.as_ref() {
        stream_sink.add(scan_progress).unwrap();
    }
}

pub(crate) fn send_state_update(update: StateUpdate) {
    let stream_sink = STATE_UPDATE_STREAM_SINK.lock().unwrap();
    if let Some(stream_sink) = stream_sink.as_ref() {
        stream_sink.add(update).unwrap();
    }
}
