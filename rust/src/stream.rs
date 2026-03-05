use std::{
    collections::{HashMap, HashSet},
    sync::Mutex,
};

use crate::frb_generated::StreamSink;
use lazy_static::lazy_static;
use spdk_wallet::{
    bitcoin::{absolute::Height, BlockHash, OutPoint},
    updater::DiscoveredOutput,
};

lazy_static! {
    static ref SCAN_PROGRESS_STREAM_SINK: Mutex<Option<StreamSink<u32>>> = Mutex::new(None);
    static ref STATE_UPDATE_STREAM_SINK: Mutex<Option<StreamSink<StateUpdate>>> = Mutex::new(None);
}

#[derive(Debug)]
pub struct StateUpdate {
    pub(crate) blkheight: Height,
    pub(crate) blkhash: BlockHash,
    pub(crate) found_outputs: HashMap<OutPoint, DiscoveredOutput>,
    pub(crate) found_inputs: HashSet<OutPoint>,
}

pub fn create_sync_progress_stream(s: StreamSink<u32>) {
    let mut stream_sink = SCAN_PROGRESS_STREAM_SINK.lock().unwrap();
    *stream_sink = Some(s);
}

pub fn create_sync_update_stream(s: StreamSink<StateUpdate>) {
    let mut stream_sink = STATE_UPDATE_STREAM_SINK.lock().unwrap();
    *stream_sink = Some(s);
}

pub(crate) fn send_sync_progress(scan_progress: u32) {
    let stream_sink = SCAN_PROGRESS_STREAM_SINK.lock().unwrap();
    if let Some(stream_sink) = stream_sink.as_ref() {
        stream_sink.add(scan_progress).unwrap();
    }
}

pub(crate) fn send_sync_update(update: StateUpdate) {
    let stream_sink = STATE_UPDATE_STREAM_SINK.lock().unwrap();
    if let Some(stream_sink) = stream_sink.as_ref() {
        stream_sink.add(update).unwrap();
    }
}
