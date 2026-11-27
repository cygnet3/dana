# Dana Wallet — Behavior Specification

**Status: DRAFT v0.1 (2026-11-13) — drafted by the lane agent from BIP-352 semantics and observed
on-device behavior. Owner review pending: every line is open to correction until Sosthene has
reviewed it. Owner corrections are authoritative and REPLACE the drafted line in full.**

This document is the app's documentation of what it is supposed to do, and the authoritative
reference for the frigate-v3 lane's user-testing step. It lives in the repo and versions with
the app.

## How this document is used

1. **Authoritative for testing.** Every user-testing case cites behavior IDs (`B<n>.<m>`). A
   case PASSes when the observed behavior matches the cited lines; a mismatch is a Finding
   card that cites the violated IDs. No case may assert behavior not written here — if a case
   needs a rule this file lacks, the rule gets added here first (owner correction or, for
   mechanical facts, a drafted line marked for review).
2. **Honest about gaps.** Lines marked `[OPEN → <card>]` describe behavior the app does not
   yet meet, tracked by their finding card. They convert to plain contract lines when the fix
   lands and a verification case PASSes.
3. **Pinned, not floating.** Dispatch prompts pin the commit of this file that was tested, so
   a verdict is always "PASS against spec @ <sha>".
4. **Not weakenable to go green.** This file changes only via owner correction or a
   landed-and-verified fix — never in the same commit as a change that was failing a case,
   and never to make a failing case pass. (Same discipline as a quality bar: tightening is
   silent, loosening is loud.)

## 0. Conventions and rig facts

- Dev flavor only on the test device (`dev.silentpayments.danawallet.dev`), regtest network.
- Regtest rig (caller-side, must work before dispatch per PIPELINE.md pre-flight): bitcoind
  v30.3 regtest, electrs 0.11.1 :60401, frigate regtest :50002 (indexes mempool ONLY at
  process start), sp-pay funding helper at `/home/hermes/tools/sp-pay/`.
- Backends: **frigate** (self-hosted Electrum-protocol indexer) and **blindbit** (public
  service). Regtest address hrp is `sprt1` (BIP-352 v0, bech32m).
- Evidence norms: screenshots, `adb shell uiautomator dump`, logcat greps; evidence paths
  recorded in the case card.

## 1. Wallet lifecycle & onboarding

- **B1.1** Fresh install (equivalent to `pm clear`) starts onboarding; no state from a
  previous wallet survives.
- **B1.2** Wallet creation generates the BIP-352 keypair material (scan/spend) on device.
  `[DRAFT-UNCORRECTED: backup/seed UX to be specified by owner]`
- **B1.3** Killing and relaunching the app preserves wallet, settings, and backend
  configuration; onboarding never reappears for an existing wallet.
- **B1.4** The receive screen shows the wallet's silent payment address: `sprt1…`, version 0,
  valid bech32m checksum, displayed space-grouped for readability but copied unspaced.
- **B1.5** The displayed address decodes to exactly the wallet's scan and spend public keys
  (verifiable with an independent BIP-352 decoder).

## 2. Receive & discovery

- **B2.1** A payment made to the displayed address is discovered and reflected in balance
  once the backend has indexed it (mempool leg and/or block leg, per backend capability).
- **B2.2** Discovery is chain-consistent: only transactions on the selected backend's chain
  or mempool are counted. Data from any other chain never affects balance or history.
- **B2.3** Balance equals the sum of discovered, unspent silent-payment outputs. With no
  funds, balance is 0 behind an explicit empty state ("Fund your wallet" + the address),
  never a blank or error screen.
- **B2.4** A payment moves pending → confirmed as its transaction confirms; the UI reflects
  the transition without user action beyond normal sync.
- **B2.5** A mempool-indexed payment is not lost or double-counted across frigate restarts,
  app restarts, or backend switches (commit-then-resume semantics: discovery state commits
  before switching/resuming, never scans the same output twice into balance).
- **B2.6** Discovery survives app restart mid-sync: after relaunch, sync resumes from the
  committed state and reaches the same balance without user action.

## 3. Send / spend

- **B3.1** Send requires sufficient available balance; attempting more shows an inline error
  and broadcasts nothing.
- **B3.2** The built transaction: sender secret is the sum of eligible input private keys
  (BIP-352); the SP output is a valid tweaked P2TR output for the destination address; change
  returns to the wallet. (Structural correctness verifiable on regtest via bitcoind + an
  independent scanner.)
- **B3.3** Broadcast goes through the selected backend; success means the transaction is in
  the regtest mempool (verifiable via `getrawmempool`).
- **B3.4** After broadcast, balance decreases by amount + fee; the fee is shown before
  confirmation.
- **B3.5** The sent transaction appears in the app's transaction list immediately (pending
  state acceptable) and persists across restarts.
- **B3.6** A failed broadcast (backend rejects/down) leaves balance and history unchanged and
  reports a human-readable error; the spend can be retried.

## 4. Backend configuration

- **B4.1** Default backend is the public blindbit URL; a fresh wallet scans against it until
  configured otherwise.
- **B4.2** Configuring a frigate URL: the URL is probed before saving. On probe failure the
  dialog STAYS OPEN with a persistent inline field error (no raw internals such as
  `AnyhowException`/`os error N`, no transient-only snackbar), the typed URL is preserved,
  and the confirm button is disabled while probing. `[landed @ fef4ce1]`
- **B4.3** A valid URL saves, persists across app restart, and is pre-filled on reopen.
- **B4.4** Switching backend mid-session commits scanning state first, then resumes on the
  new backend from the committed height — no lost state, no error spam, no rescan from zero
  unless required by chain inconsistency.
- **B4.5** While a custom backend URL is configured, the app talks to that endpoint only for
  backend services — no silent fallback to a default URL.

## 5. Chain consistency & tip integrity

- **B5.1** The chain tip used for scanning and progress indication comes ONLY from the
  selected backend's session. `[OPEN → t_find_tip_blindbit: with frigate selected, tip
  updates still arrive from the default blindbit URL (foreign chain, 523 vs 852)]`
- **B5.2** Tips, headers, or transactions not consistent with the selected backend's chain
  are rejected, not merged into chain state.
- **B5.3** Progress indicators ("-N blocks to scan" and similar) reflect the selected
  backend's tip only; on a synced wallet none may appear. `[OPEN → t_ut_stale_warning]`

## 6. Resilience & recovery

- **B6.1** While the backend is unreachable, the app shows an explicit banner ("Frigate
  unreachable — will retry at next sync"); the periodic sync keeps retrying; no crash, no
  data loss, no silent fallback.
- **B6.2** The unreachable banner clears on the next successful sync. `[OPEN →
  t_find_banner_stale: banner persisted 20+ min across healthy syncs]`
- **B6.3** Recovery from a short backend outage requires no manual intervention: the sync
  engine reconnects on its own and the UI returns to normal (banner cleared, balances
  current) without the user re-entering settings.
- **B6.4** All user-visible errors are human-readable; internal error types, stack fragments,
  and OS error codes never appear in the UI.

## 7. Contacts & labels (sender-side)

**Section drafted from observation; owner correction pending — treat IDs here as provisional.**

- **B7.1** Labels/contacts are sender-side records: attached locally by the sender to a
  destination or payment. They are not derivable from on-chain data and not part of the
  silent payment address.
- **B7.2** Sending to a saved contact uses its stored SP address verbatim (no rewriting, no
  reuse of a previous transaction's derived output keys as the send target).
- **B7.3** The transaction list can associate a sent payment with its locally stored label;
  labels survive app restart.

## 8. UX polish & feedback states

- **B8.1** Irreversible actions (send, wallet operations) confirm before executing.
- **B8.2** In-flight actions disable their control and show progress; a double-tap cannot
  double-submit (no double broadcast, no duplicate request).
- **B8.3** Every screen has an explicit empty/loading state; no blank screens and no raw
  error dumps as content.
- **B8.4** Copy affordances copy exact values (address unspaced, amounts normalized) and
  confirm the copy happened.
- **B8.5** Navigation state survives brief interruptions (screen off, app switch) without
  resetting flows; dialogs are never dismissed by an unrelated background event.

## Appendix: known open deviations

| IDs | Deviation | Tracking card |
|-----|-----------|---------------|
| B5.1, B5.3 | Foreign blindbit tip accepted while frigate selected; phantom "-N blocks" | `t_find_tip_blindbit` |
| B6.2 | Unreachable banner persists after engine recovery | `t_find_banner_stale` |
| B2.1 | Funded payment not discovered despite healthy sync (root cause TBD) | `t_find_sync_nodiscovery` |
