//! Phase-3 electrum confirmation tracking (decision-record amendment
//! 2026-11-10, phase 3).
//!
//! The frigate mempool leg (phase 2) only registers candidates. Confirmation
//! is tracked against a **regular electrum server** session: every
//! mempool-discovered output script is registered via
//! `blockchain.scripthash.subscribe`, and the server's scripthash status
//! notification drives a `blockchain.scripthash.get_history` lookup whose
//! confirmed entries create wallet state through the shared pump —
//! deduped against phase-1 `Confirmed` re-reports (exact-once).
//!
//! Electrum server selection (implementation decision, same amendment): the
//! configured frigate backend URL is itself a full electrum server and
//! implements `scripthash.subscribe`; pointing the scripthash subscription
//! at it discloses nothing the frigate operator does not already know (the
//! registered scripthashes are outputs the operator's own scan produced).
//! No scan key and no new key material ever crosses this session — it is a
//! plain watch-only electrum connection.

use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex, MutexGuard},
    time::Duration,
};

use backend_frigate::FrigateClient;
use electrum_streaming_client::{
    notification::Notification, request::ScriptHashSubscribe, response::ConfirmedTx,
    response::Tx as HistoryTx, ElectrumScriptHash, Event,
};
use futures::{channel::mpsc::UnboundedReceiver, StreamExt as _};
use spdk_wallet::bitcoin::{ScriptBuf, Txid};

use crate::state::SyncUpdatePump;

/// Request timeout for the confirmation tracker's electrum session.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);
/// Reconnect backoff after a failed connect or a dead session. Candidates
/// stay pending meanwhile; the phase-1 re-report still creates their state,
/// so nothing is lost to tracker downtime.
const RECONNECT_BACKOFF: Duration = Duration::from_secs(5);

/// Confirmation matcher: the watched candidate txids that appear as
/// CONFIRMED history entries (height > 0). Mempool entries (not yet mined)
/// and foreign txids never count — only a real block height confirms.
///
/// `#[frb(ignore)]`: pure Rust helper (tests + tracker internals), never
/// called from Dart. Exposing it would drag `Txid` into the bridge, whose
/// generated codecs do not compile (auto-opaque Txid); the frigate scanner
/// delivers txids as strings across the bridge instead.
#[flutter_rust_bridge::frb(ignore)]
pub fn matched_confirmations(
    history: &[HistoryTx],
    watched: &HashSet<Txid>,
) -> HashSet<Txid> {
    history
        .iter()
        .filter_map(|tx| match tx {
            HistoryTx::Confirmed(ConfirmedTx { txid, .. }) if watched.contains(txid) => {
                Some(*txid)
            }
            _ => None,
        })
        .collect()
}

/// Confirmation-tracker task: consumes candidate scripthash registrations
/// from the frigate monitor, subscribes them on a regular electrum session,
/// and turns scripthash notifications into pump confirmations.
///
/// `pump` is shared with the monitor event loop; the tracker only ever calls
/// the exact-once-guarded [`SyncUpdatePump::confirm_candidates`]. Ends when
/// the registration channel closes (monitor stopped): sessions are not kept
/// alive for an app that no longer runs the monitor.
pub(crate) async fn run_confirmation_tracker(
    electrum_url: String,
    pump: Arc<Mutex<SyncUpdatePump>>,
    mut registrations: UnboundedReceiver<(ScriptBuf, Txid)>,
) {
    // scripthash → candidate txids whose outputs carry that script.
    let mut watched: HashMap<ElectrumScriptHash, HashSet<Txid>> = HashMap::new();

    loop {
        let shutdown = match FrigateClient::connect(&electrum_url, Some(REQUEST_TIMEOUT)).await {
            Ok(client) => {
                log::info!(
                    "frigate confirmation tracker: electrum session open on {electrum_url}"
                );
                // A fresh session must re-subscribe everything watched so
                // far: the server holds no state for a dead connection.
                let session = ElectrumSession {
                    subscribed: HashSet::new(),
                };
                session
                    .run(client, &pump, &mut registrations, &mut watched)
                    .await
            }
            Err(err) => {
                log::warn!("frigate confirmation tracker: connect failed: {err}");
                // While disconnected, drain new registrations into `watched`
                // so they are subscribed on the next session, and honour
                // shutdown instead of looping on a dead channel.
                wait_for_registration_or_shutdown(&mut registrations, &mut watched).await
            }
        };
        if matches!(shutdown, SessionEnd::Shutdown) {
            return;
        }
        tokio::time::sleep(RECONNECT_BACKOFF).await;
    }
}

/// Drains registrations while the tracker has no live electrum session.
/// Returns `SessionEnd::Shutdown` when the monitor shut the tracker down.
async fn wait_for_registration_or_shutdown(
    registrations: &mut UnboundedReceiver<(ScriptBuf, Txid)>,
    watched: &mut HashMap<ElectrumScriptHash, HashSet<Txid>>,
) -> SessionEnd {
    while let Some((script, txid)) = registrations.next().await {
        record_watched(watched, script, txid);
    }
    SessionEnd::Shutdown
}

fn record_watched(
    watched: &mut HashMap<ElectrumScriptHash, HashSet<Txid>>,
    script: ScriptBuf,
    txid: Txid,
) -> ElectrumScriptHash {
    let script_hash = ElectrumScriptHash::new(&script);
    watched.entry(script_hash).or_default().insert(txid);
    script_hash
}

/// One live electrum session: subscriptions plus the notification loop.
struct ElectrumSession {
    subscribed: HashSet<ElectrumScriptHash>,
}

enum SessionEnd {
    /// The monitor stopped; the tracker must exit.
    Shutdown,
    /// The connection died; the tracker reconnects.
    ConnectionLost,
}

impl ElectrumSession {
    async fn run(
        mut self,
        mut client: FrigateClient,
        pump: &Arc<Mutex<SyncUpdatePump>>,
        registrations: &mut UnboundedReceiver<(ScriptBuf, Txid)>,
        watched: &mut HashMap<ElectrumScriptHash, HashSet<Txid>>,
    ) -> SessionEnd {
        // (Re-)subscribe everything already watched, then process live
        // registrations and scripthash notifications until the session or
        // the monitor ends.
        let existing: Vec<ElectrumScriptHash> = watched.keys().copied().collect();
        for script_hash in existing {
            self.subscribe_and_prime(&client, pump, watched, script_hash)
                .await;
        }

        loop {
            // `biased` + registrations first: shutdown is deterministic even
            // with notifications queued. Both `next()` futures are
            // cancellation-safe (the receivers only pop an item when it is
            // actually returned).
            tokio::select! {
                biased;
                registration = registrations.next() => match registration {
                    Some((script, txid)) => {
                        let script_hash = record_watched(watched, script, txid);
                        self.subscribe_and_prime(&client, pump, watched, script_hash).await;
                    }
                    None => return SessionEnd::Shutdown,
                },
                event = client.events.next() => match event {
                    Some(Event::Notification(notification)) => {
                        let script_hash = match notification {
                            Notification::ScriptHash(n) => n.script_hash(),
                            _ => continue,
                        };
                        let Some(watched_txids) = watched.get(&script_hash) else {
                            continue;
                        };
                        self.handle_status(&client, pump, script_hash, watched_txids)
                            .await;
                    }
                    // tracked responses (our own subscribes/lookups) and
                    // anything unrecognized are not confirmation signals
                    Some(_) => continue,
                    None => return SessionEnd::ConnectionLost,
                },
            };
        }
    }

    /// Subscribes `script_hash` once per session; a non-empty initial status
    /// means the script already had activity before we subscribed (the
    /// candidate may have confirmed in that window) and is primed like a
    /// notification.
    async fn subscribe_and_prime(
        &mut self,
        client: &FrigateClient,
        pump: &Arc<Mutex<SyncUpdatePump>>,
        watched: &HashMap<ElectrumScriptHash, HashSet<Txid>>,
        script_hash: ElectrumScriptHash,
    ) {
        if !self.subscribed.insert(script_hash) {
            return;
        }
        let status = match client
            .scripthash_subscribe(ScriptHashSubscribe { script_hash })
            .await
        {
            Ok(status) => status,
            Err(err) => {
                // e.g. a backend without scripthash support: keep the
                // candidate pending (the phase-1 re-report still creates its
                // state) and retry on the next session.
                self.subscribed.remove(&script_hash);
                log::warn!(
                    "frigate confirmation tracker: scripthash subscribe failed: {err}"
                );
                return;
            }
        };
        if status.is_some() {
            if let Some(watched_txids) = watched.get(&script_hash) {
                self.handle_status(client, pump, script_hash, watched_txids)
                    .await;
            }
        }
    }

    /// A scripthash status change: fetch the history and confirm every
    /// watched candidate txid that is now mined at a real height.
    async fn handle_status(
        &self,
        client: &FrigateClient,
        pump: &Arc<Mutex<SyncUpdatePump>>,
        script_hash: ElectrumScriptHash,
        watched_txids: &HashSet<Txid>,
    ) {
        if watched_txids.is_empty() {
            return;
        }
        let history = match client.get_history(script_hash).await {
            Ok(history) => history,
            Err(err) => {
                log::warn!("frigate confirmation tracker: get_history failed: {err}");
                return;
            }
        };
        let confirmed = matched_confirmations(&history, watched_txids);
        for txid in confirmed {
            // mined height of this txid from its confirmed history entry
            let Some(height) = history.iter().find_map(|tx| match tx {
                HistoryTx::Confirmed(ConfirmedTx { txid: entry, height }) if *entry == txid => {
                    Some(height.to_consensus_u32())
                }
                _ => None,
            }) else {
                continue;
            };
            // The block hash rides the header at that height; on failure the
            // confirmation is skipped — the candidate stays pending and the
            // phase-1 re-report creates its state (no receipt lost).
            let blkhash = match client.get_block_header(height).await {
                Ok(header) => header.header.block_hash().to_string(),
                Err(err) => {
                    log::warn!(
                        "frigate confirmation tracker: header at {height} unavailable: {err}"
                    );
                    continue;
                }
            };
            let txids = HashSet::from([txid]);
            match lock_pump(pump).confirm_candidates(&txids, height, &blkhash) {
                Ok(emitted) if emitted > 0 => {
                    log::info!(
                        "frigate confirmation tracker: candidate confirmed at {height} (state created)"
                    );
                }
                Ok(_) => {}
                Err(err) => {
                    log::warn!("frigate confirmation tracker: confirm failed: {err}");
                }
            }
        }
    }
}

/// Locks the shared pump, recovering from a poisoned guard (a panicked
/// monitor must not take the tracker down with it).
fn lock_pump(pump: &Arc<Mutex<SyncUpdatePump>>) -> MutexGuard<'_, SyncUpdatePump> {
    pump.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}
