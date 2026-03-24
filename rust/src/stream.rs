use std::{
    collections::HashSet,
    sync::Mutex,
};

use crate::{
    api::structs::amount::ApiAmount, frb_generated::StreamSink
};
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;

lazy_static! {
    static ref SCAN_PROGRESS_STREAM_SINK: Mutex<Option<StreamSink<u32>>> = Mutex::new(None);
    static ref STATE_UPDATE_STREAM_SINK: Mutex<Option<StreamSink<StateUpdate>>> = Mutex::new(None);
}

#[derive(Debug)]
#[frb]
pub struct StateUpdate {
    pub blkheight: u32,
    pub blkhash: String,
    pub found_outputs: Vec<OwnedOutput>,
    pub found_inputs: HashSet<String>,
}

#[derive(Debug, Clone)]
#[frb]
pub struct OwnedOutput {
    pub txid: String,
    pub vout: u32,
    pub blockheight: u32,
    pub tweak: [u8; 32],
    pub amount: ApiAmount,
    pub script: String,
    pub label: Option<String>,
    pub spending_txid: Option<String>,
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
