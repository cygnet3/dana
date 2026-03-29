use std::collections::HashMap;

use anyhow::Result;
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use spdk_wallet::{
    bitcoin::{Amount, OutPoint, ScriptBuf},
    silentpayments::receiving::Label,
};

use crate::api::structs::owned_output::OwnedOutput;

#[derive(Debug, Clone, Deserialize, Serialize)]
#[frb(opaque)]
pub struct LegacyOwnedOutputsStruct(HashMap<OutPoint, LegacyOwnedOutputStruct>);

#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct LegacyOwnedOutputStruct {
    tweak: [u8; 32], // scalar in big endian format
    amount: Amount,
    script: ScriptBuf,
    label: Option<Label>,
}

impl LegacyOwnedOutputsStruct {
    /// Decode transaction history from JSON string.
    /// Only used during migration from SharedPreferences to SQLite.
    #[flutter_rust_bridge::frb(sync)]
    pub fn decode(encoded_outputs: String) -> Result<Self> {
        let deserialized = serde_json::from_str(&encoded_outputs)?;

        Ok(deserialized)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn encode(&self) -> Result<String> {
        Ok(serde_json::to_string(&self)?)
    }

    /// Convert to API transaction list for migration.
    /// Only used during migration from SharedPreferences to SQLite.
    #[flutter_rust_bridge::frb(sync)]
    pub fn to_api_owned_outputs(&self) -> Vec<OwnedOutput> {
        self.0.clone().into_iter().map(|x| x.into()).collect()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn from_api_owned_outputs(owned_outputs: Vec<OwnedOutput>) -> Self {
        Self(owned_outputs.into_iter().map(Into::into).collect())
    }
}

impl From<(OutPoint, LegacyOwnedOutputStruct)> for OwnedOutput {
    fn from((outpoint, value): (OutPoint, LegacyOwnedOutputStruct)) -> Self {
        OwnedOutput {
            outpoint: outpoint.into(),
            tweak: value.tweak,
            amount: value.amount.into(),
            script: value.script.to_bytes(),
            label: value.label.map(|l| l.as_string()),
        }
    }
}

impl From<OwnedOutput> for (OutPoint, LegacyOwnedOutputStruct) {
    fn from(value: OwnedOutput) -> (OutPoint, LegacyOwnedOutputStruct) {
        (
            value.outpoint.into(),
            LegacyOwnedOutputStruct {
                tweak: value.tweak,
                amount: value.amount.into(),
                script: ScriptBuf::from_bytes(value.script),
                label: value.label.map(|l| l.try_into().unwrap()),
            },
        )
    }
}
