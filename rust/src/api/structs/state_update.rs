use std::collections::HashSet;

use flutter_rust_bridge::frb;

use crate::api::structs::outpoint::OutPoint;
use crate::api::structs::owned_output::OwnedOutput;

#[derive(Debug)]
#[frb]
pub struct StateUpdate {
    pub blkheight: u32,
    pub blkhash: String,
    pub found_outputs: Vec<OwnedOutput>,
    pub found_inputs: HashSet<OutPoint>,
}
