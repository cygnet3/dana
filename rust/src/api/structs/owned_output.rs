use flutter_rust_bridge::frb;

use crate::api::structs::amount::Amount;
use crate::api::structs::outpoint::OutPoint;

#[derive(Debug, Clone)]
#[frb]
pub struct OwnedOutput {
    pub outpoint: OutPoint,
    pub tweak: [u8; 32],
    pub amount: Amount,
    pub script: Vec<u8>,
    pub label: Option<[u8; 32]>,
}
