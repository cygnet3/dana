use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

use crate::state::constants::RecordedTransaction;

use super::structs::recorded_transaction::ApiRecordedTransaction;
use anyhow::Result;

/// Legacy TxHistory type for migration only.
/// DO NOT USE in new code - use SQLite-backed transaction storage instead.
/// Only kept for reading old wallet data from SharedPreferences during migration.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[frb(opaque)]
pub struct TxHistory(Vec<RecordedTransaction>);

impl TxHistory {
    /// Create an empty transaction history.
    /// Only used for migration/backup compatibility.
    #[flutter_rust_bridge::frb(sync)]
    pub fn empty() -> Self {
        Self(vec![])
    }

    /// Decode transaction history from JSON string.
    /// Only used during migration from SharedPreferences to SQLite.
    #[flutter_rust_bridge::frb(sync)]
    pub fn decode(encoded_history: String) -> Result<Self> {
        let decoded: Vec<ApiRecordedTransaction> = serde_json::from_str(&encoded_history)?;
        Ok(Self(decoded.into_iter().map(Into::into).collect()))
    }

    /// Convert to API transaction list for migration.
    /// Only used during migration from SharedPreferences to SQLite.
    #[flutter_rust_bridge::frb(sync)]
    pub fn to_api_transactions(&self) -> Vec<ApiRecordedTransaction> {
        self.0.iter().map(|x| x.clone().into()).collect()
    }
}
