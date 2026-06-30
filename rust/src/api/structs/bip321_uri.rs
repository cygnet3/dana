use serde::{Deserialize, Serialize};

use crate::api::structs::amount::Amount;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Bip321Uri {
    pub sp: Vec<String>,
    pub tsp: Vec<String>,
    pub bc: Vec<String>,
    pub tb: Vec<String>,
    pub address: Option<String>,
    pub amount: Option<Amount>,
}
