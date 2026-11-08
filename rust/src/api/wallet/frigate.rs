use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

use anyhow::Result;
use futures::StreamExt as _;
use lazy_static::lazy_static;
use spdk_wallet::bitcoin::absolute::Height;
use spdk_wallet::bitcoin::{BlockHash, OutPoint, ScriptBuf};

use crate::state::SyncUpdatePump;
use crate::stream::send_sync_progress;

use super::SpWallet;
use frigate::{FrigateEvent, FrigateHandle, FrigateScanner};

lazy_static! {
    /// Background monitor task; aborting it drops the `FrigateHandle`, which
    /// aborts the scanner worker and closes the frigate connection.
    static ref FRIGATE_MONITOR: Mutex<Option<tokio::task::JoinHandle<()>>> = Mutex::new(None);
}

/// An owned output the frigate scanner keeps watching for spends.
///
/// Frigate re-delivers silent payment history only from the requested start
/// height, so the scanner re-subscribes these outputs' scripts on `start` and
/// sweeps their history once — that is what makes spends detected while the
/// wallet was offline surface as `FrigateEvent::Spent`.
#[derive(Debug, Clone)]
pub struct WatchedOutput {
    pub outpoint: crate::api::structs::outpoint::OutPoint,
    pub script: Vec<u8>,
}

impl SpWallet {
    async fn build_frigate_scanner(
        &self,
        frigate_url: String,
        watched_outputs: Vec<WatchedOutput>,
    ) -> Result<FrigateScanner> {
        let mut previous_outputs: HashMap<ScriptBuf, HashSet<OutPoint>> = HashMap::new();
        for watched in watched_outputs {
            let outpoint: OutPoint = watched.outpoint.into();
            previous_outputs
                .entry(ScriptBuf::from_bytes(watched.script))
                .or_default()
                .insert(outpoint);
        }

        FrigateScanner::new(
            frigate_url,
            self.client.scan_key(),
            self.client.receiver(),
            // Dana does not use silent payment labels yet
            None,
            previous_outputs,
        )
        .await
    }

    /// One-shot frigate sync: subscribe from `from_height`, forward confirmed
    /// discoveries and spends through the sync streams, and return once the
    /// historical catch-up completes (checkpoint advanced to the tip).
    ///
    /// Drop-in for the hourly wake cycle; the scanner connection is closed on
    /// return. The frigate server only learns the scan key — no address or
    /// spend key ever crosses the wire.
    pub async fn sync_via_frigate(
        &self,
        frigate_url: String,
        from_height: u32,
        dust_limit: u64,
        watched_outputs: Vec<WatchedOutput>,
    ) -> Result<()> {
        let scanner = self
            .build_frigate_scanner(frigate_url, watched_outputs)
            .await?;
        let mut handle = scanner.start(Height::from_consensus(from_height)?);
        let mut pump = SyncUpdatePump::new(dust_limit);
        let mut tip: Option<(Height, BlockHash)> = None;

        while let Some(event) = handle.next().await {
            match event {
                FrigateEvent::Tip { height, hash } => {
                    tip = Some((height, hash));
                    send_sync_progress(height.to_consensus_u32());
                }
                FrigateEvent::Confirmed(scan_result) => pump.record(scan_result, false)?,
                FrigateEvent::Spent(spent) => pump.record_spent(spent)?,
                FrigateEvent::CaughtUp => {
                    if let Some((height, hash)) = tip {
                        pump.finalize(height, hash)?;
                    }
                    break;
                }
                FrigateEvent::Disconnected(reason) => {
                    anyhow::bail!("frigate connection ended: {reason}");
                }
                FrigateEvent::Unconfirmed { txid, .. } => {
                    // mempool discoveries are re-reported as Confirmed once
                    // mined; Dana's state layer only tracks confirmed outputs
                    log::debug!("frigate: mempool discovery {txid} deferred until confirmation");
                }
            }
        }

        Ok(())
    }

    /// Continuous frigate monitor for the foreground service: keeps the
    /// subscription open and streams live block/mempool/tip/spend events
    /// until `stopFrigateMonitor()` is called or the connection ends.
    ///
    /// Safe to call again: replaces any running monitor.
    pub async fn start_frigate_monitor(
        &self,
        frigate_url: String,
        from_height: u32,
        dust_limit: u64,
        watched_outputs: Vec<WatchedOutput>,
    ) -> Result<()> {
        let scanner = self
            .build_frigate_scanner(frigate_url, watched_outputs)
            .await?;
        let handle = scanner.start(Height::from_consensus(from_height)?);

        let mut guard = FRIGATE_MONITOR.lock().unwrap();
        if let Some(old) = guard.take() {
            old.abort();
        }
        *guard = Some(tokio::spawn(async move {
            monitor_pump(handle, dust_limit).await;
        }));

        Ok(())
    }
}

/// Stop the background frigate monitor (no-op if none is running).
#[flutter_rust_bridge::frb(sync)]
pub fn stop_frigate_monitor() {
    if let Some(handle) = FRIGATE_MONITOR.lock().unwrap().take() {
        handle.abort();
    }
}

async fn monitor_pump(mut handle: FrigateHandle, dust_limit: u64) {
    let mut pump = SyncUpdatePump::new(dust_limit);
    let mut caught_up = false;

    while let Some(event) = handle.next().await {
        match event {
            FrigateEvent::Tip { height, hash } => {
                // before CaughtUp the tip is progress only; afterwards each new
                // tip keeps the wallet checkpoint advancing live
                let result = if caught_up {
                    pump.finalize(height, hash)
                } else {
                    send_sync_progress(height.to_consensus_u32());
                    Ok(())
                };
                if let Err(err) = result {
                    log::warn!("frigate monitor: tip handling failed: {err}");
                }
            }
            FrigateEvent::Confirmed(scan_result) => {
                if let Err(err) = pump.record(scan_result, false) {
                    log::warn!("frigate monitor: discovery handling failed: {err}");
                }
            }
            FrigateEvent::Spent(spent) => {
                if let Err(err) = pump.record_spent(spent) {
                    log::warn!("frigate monitor: spend handling failed: {err}");
                }
            }
            FrigateEvent::CaughtUp => caught_up = true,
            FrigateEvent::Disconnected(reason) => {
                log::warn!("frigate monitor disconnected: {reason}");
                break;
            }
            FrigateEvent::Unconfirmed { .. } => {}
        }
    }
}
