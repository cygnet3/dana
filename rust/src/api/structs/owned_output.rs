use flutter_rust_bridge::frb;

use crate::api::structs::amount::Amount;
use crate::api::structs::outpoint::OutPoint;

use anyhow::Result;
use spdk_wallet::bitcoin::secp256k1::Scalar;
use spdk_wallet::bitcoin::ScriptBuf;

#[derive(Debug, Clone)]
#[frb]
pub struct OwnedOutput {
    pub outpoint: OutPoint,
    pub tweak: [u8; 32],
    pub amount: Amount,
    pub script: Vec<u8>,
    pub label: Option<[u8; 32]>,
}

/// The wallet's native UTXO representation, as used by the coin-selection
/// and transaction-construction functions.
pub(crate) type WalletUtxo = (
    spdk_wallet::bitcoin::OutPoint,
    spdk_wallet::updater::DiscoveredOutput,
);

impl OwnedOutput {
    /// Convert to the wallet's native UTXO representation.
    pub(crate) fn try_into_utxo(self) -> Result<WalletUtxo> {
        let label = match self.label {
            Some(l) => Some(Scalar::from_be_bytes(l)?.into()),
            None => None,
        };
        let output = spdk_wallet::updater::DiscoveredOutput {
            tweak: Scalar::from_be_bytes(self.tweak)?,
            value: self.amount.into(),
            script_pubkey: ScriptBuf::from_bytes(self.script),
            label,
        };
        Ok((self.outpoint.into(), output))
    }
}
