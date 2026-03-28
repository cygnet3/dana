use flutter_rust_bridge::frb;

use crate::api::structs::amount::ApiAmount;
use crate::api::structs::outpoint::OutPoint;

#[derive(Debug, Clone)]
#[frb]
pub struct OwnedOutput {
    pub outpoint: OutPoint,
    pub tweak: [u8; 32],
    pub amount: ApiAmount,
    pub script: String,
    pub label: Option<String>,
}
