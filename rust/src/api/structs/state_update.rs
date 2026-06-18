use std::collections::HashSet;

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

use crate::api::structs::outpoint::OutPoint;
use crate::api::structs::owned_output::OwnedOutput;

#[derive(Debug, Serialize, Deserialize)]
#[frb]
pub struct StateUpdate {
    pub blkheight: u32,
    pub blkhash: String,
    pub found_outputs: Vec<OwnedOutput>,
    pub found_inputs: HashSet<OutPoint>,
}

impl StateUpdate {
    // these encode and decode functions are used to send the state update betweeen the flutter
    // foreground thread and the main isolate, since only primitive types are allowed
    #[frb(sync)]
    pub fn decode(encoded: String) -> Self {
        serde_json::from_str(&encoded).unwrap()
    }

    #[frb(sync)]
    pub fn encode(&self) -> String {
        serde_json::to_string(self).unwrap()
    }
}
