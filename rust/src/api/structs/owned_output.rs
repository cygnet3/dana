use flutter_rust_bridge::frb;

use crate::api::structs::amount::ApiAmount;

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
}
