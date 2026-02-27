use std::{
    collections::{HashMap, HashSet},
    str::FromStr,
};

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use spdk_wallet::{bitcoin::{Amount, OutPoint, ScriptBuf, absolute::Height}, silentpayments::receiving::Label};

use anyhow::Result;

use crate::api::structs::owned_output::ApiOwnedOutput;

#[frb(opaque)]
pub struct OwnedOutPoints(HashSet<OutPoint>);

impl OwnedOutPoints {
    pub(crate) fn to_inner(self) -> HashSet<OutPoint> {
        self.0
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct OwnedOutput {
    pub(crate) blockheight: Height,
    pub(crate) tweak: [u8; 32], // scalar in big endian format
    pub(crate) amount: Amount,
    pub(crate) script: ScriptBuf,
    pub(crate) label: Option<Label>,
    pub(crate) spend_status: OutputSpendStatus,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub(crate) enum OutputSpendStatus {
    Unspent,
    Spent([u8; 32]),
    Mined([u8; 32]),
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[frb(opaque)]
pub struct OwnedOutputs(HashMap<OutPoint, OwnedOutput>);

impl OwnedOutputs {
    #[flutter_rust_bridge::frb(sync)]
    pub fn empty() -> Self {
        Self(HashMap::new())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn decode(encoded_outputs: String) -> Result<Self> {
        let decoded: HashMap<String, ApiOwnedOutput> = serde_json::from_str(&encoded_outputs)?;

        let mut res: HashMap<OutPoint, OwnedOutput> = HashMap::new();

        for (outpoint, output) in decoded.into_iter() {
            res.insert(OutPoint::from_str(&outpoint)?, output.into());
        }

        Ok(Self(res))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn encode(&self) -> Result<String> {
        let mut encoded: HashMap<String, ApiOwnedOutput> = HashMap::new();

        for (outpoint, output) in self.0.iter() {
            encoded.insert(outpoint.to_string(), output.clone().into());
        }

        Ok(serde_json::to_string(&encoded)?)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn get_unspent_outputs(&self) -> HashMap<String, ApiOwnedOutput> {
        let mut res = HashMap::new();
        for (outpoint, output) in self.0.iter() {
            if output.spend_status == OutputSpendStatus::Unspent {
                res.insert(outpoint.to_string(), output.clone().into());
            }
        }

        res
    }
}
