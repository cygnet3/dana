import 'dart:async';

import 'package:danawallet/constants.dart'
    show frigateNoUrlMsg, frigateOfflineMsg;
import 'package:danawallet/generated/rust/api/structs/frigate_scan_outcome.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/structs/state_update.dart';
import 'package:danawallet/generated/rust/api/wallet.dart' show SpWallet;
import 'package:danawallet/generated/rust/api/wallet/frigate.dart'
    show FrigateTipProbe, WatchedOutput;
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/services/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// D10 acceptance list: wake-flow behaviors.
///
/// Drives [SyncEngine.trySync] end-to-end with in-memory stores and
/// counting fakes for the rust calls — no rust library, no network.
void main() {
  late FakeWalletStore wallet;
  late FakeSettingsStore settings;
  int probeCalls = 0;
  int watchCalls = 0;
  int scanCalls = 0;
  final scanCallsWith = <({String url, int fromHeight})>[];
  int chainHeightCalls = 0;
  int networkCheckCalls = 0;
  final banners = <String>[];
  int recoveredCalls = 0;
  int? syncStartedEnd;
  bool? completedWith;

  // Probe tip the fakes report (server-authoritative tip, D3); null = unreachable.
  // The probe also reports the backend's chain (chain-consistency fix):
  // probeNetwork is the chain the fake backend follows, signet = the fake
  // wallet's own network.
  void setProbeTip(int? height) => settings.probeTip = height == null
      ? null
      : FrigateTipProbe(
          tipHeight: height,
          tipHash: 'deadbeef',
          network: settings.probeNetwork,
        );

  SyncEngine buildEngine() => SyncEngine(
        onSyncStarted: (start, end) => syncStartedEnd = end,
        onSyncComplete: (success) => completedWith = success,
        onStateUpdated: (_) async {},
        onTransientOffline: (message) => banners.add(message),
        onRecovered: () => recoveredCalls++,
        walletRepository: wallet,
        settingsRepository: settings,
        frigateProbe: ({required url}) async {
          probeCalls++;
          final tip = settings.probeTip;
          if (tip == null) throw Exception('unreachable frigate');
          return tip;
        },
        watchedOutputsFn: () async {
          watchCalls++;
          return const <WatchedOutput>[];
        },
        frigateScanFn: (
            {required frigateUrl,
            required fromHeight,
            required dustLimit,
            required watchedOutputs}) async {
          scanCalls++;
          scanCallsWith.add((url: frigateUrl, fromHeight: fromHeight));
          return const FrigateScanOutcome_Completed();
        },
        chainHeightFn: ({required blindbitUrl}) async {
          chainHeightCalls++;
          return settings.probeTip?.tipHeight ?? 500;
        },
        networkCheckFn: ({required blindbitUrl, required network}) async {
          networkCheckCalls++;
          return true;
        },
        resultStreamFn: () => const Stream<StateUpdate>.empty(),
      );

  setUp(() {
    wallet = FakeWalletStore();
    settings = FakeSettingsStore();
    probeCalls = 0;
    watchCalls = 0;
    scanCalls = 0;
    scanCallsWith.clear();
    chainHeightCalls = 0;
    networkCheckCalls = 0;
    banners.clear();
    recoveredCalls = 0;
    syncStartedEnd = null;
    completedWith = null;
    settings.backend = frigateBackendFrigate;
    settings.frigateUrl = 'ssl://frigate.example:50002';
    setProbeTip(600);
  });

  group('idle wake is a no-op when caught up (D3, no history re-sweep)', () {
    test('probe says caught-up -> zero scans, zero watch-set disclosures',
        () async {
      wallet.lastSync = 600; // == probe tip: up to date.

      await buildEngine().trySync();

      expect(probeCalls, 1, reason: 'catch-up is derived, not remembered');
      expect(scanCalls, 0, reason: 'no syncViaFrigate when caught up');
      expect(watchCalls, 0, reason: 'watch set never re-disclosed');
      expect(wallet.disclosures, isEmpty,
          reason: 'no subscribe -> no disclosure record');
      expect(banners, isEmpty);
      expect(wallet.savedHeights, isEmpty,
          reason: 'checkpoint untouched by an idle wake');
      expect(completedWith, isNull,
          reason: 'no onSyncStarted -> no completion either');
    });

    test('probe tip ahead by one block -> exactly one scan from lastSync+1',
        () async {
      wallet.lastSync = 599;

      await buildEngine().trySync();

      expect(probeCalls, 1);
      expect(scanCalls, 1);
      expect(scanCallsWith.single.fromHeight, 600,
          reason: 'start_height prevents history re-sweeping');
      expect(watchCalls, 1,
          reason: 'single disclosure point, reached only for a real scan');
      expect(wallet.disclosures.single['url'], 'ssl://frigate.example:50002');
      expect(syncStartedEnd, 600, reason: 'real end height up front (D4)');
      expect(completedWith, true);
    });
  });

  group('offline handling (D8)', () {
    test('probe failure -> transient banner, nothing touched, auto-resume',
        () async {
      wallet.lastSync = 599;
      setProbeTip(null); // probe will throw

      await buildEngine().trySync();

      expect(banners, [frigateOfflineMsg]);
      expect(scanCalls, 0);
      expect(watchCalls, 0);
      expect(wallet.disclosures, isEmpty);
      expect(wallet.savedHeights, isEmpty,
          reason: 'checkpoint untouched on probe failure');
      expect(wallet.lock, isNull);

      // Auto-resume: the next wake (tip reachable again) scans normally.
      setProbeTip(600);
      await buildEngine().trySync();
      expect(scanCalls, 1);
      expect(scanCallsWith.single.fromHeight, 600);
    });

    test('Disconnected outcome -> banner + normal completion, checkpoint kept',
        () async {
      wallet.lastSync = 599;

      final engineWithDisconnect = SyncEngine(
        onSyncStarted: (start, end) => syncStartedEnd = end,
        onSyncComplete: (success) => completedWith = success,
        onStateUpdated: (_) async {},
        onTransientOffline: (message) => banners.add(message),
        onRecovered: () => recoveredCalls++,
        walletRepository: wallet,
        settingsRepository: settings,
        frigateProbe: ({required url}) async => const FrigateTipProbe(
          tipHeight: 600,
          tipHash: 'deadbeef',
          network: Network.signet,
        ),
        watchedOutputsFn: () async => const <WatchedOutput>[],
        frigateScanFn: (
            {required frigateUrl,
            required fromHeight,
            required dustLimit,
            required watchedOutputs}) async {
          scanCalls++;
          return const FrigateScanOutcome_Disconnected(
              reason: 'connection closed');
        },
        resultStreamFn: () => const Stream<StateUpdate>.empty(),
      );

      await engineWithDisconnect.trySync();

      expect(scanCalls, 1);
      expect(banners, [frigateOfflineMsg],
          reason: 'neutral transient banner, no red error');
      expect(completedWith, true,
          reason: 'Disconnected is a normal outcome, not an error path');
      expect(wallet.lock, isNull, reason: 'scan lock cleared');
    });
  });

  group('offline banner recovery (t_find_banner_stale)', () {
    test('probe failure does not signal recovery', () async {
      wallet.lastSync = 600;
      setProbeTip(null); // probe will throw

      await buildEngine().trySync();

      expect(banners, [frigateOfflineMsg]);
      expect(recoveredCalls, 0,
          reason: 'no successful frigate round-trip happened');
    });

    test('up-to-date wake after a probe failure signals recovery', () async {
      wallet.lastSync = 600;
      setProbeTip(null);
      await buildEngine().trySync();
      expect(banners, [frigateOfflineMsg]);

      // Frigate is back: the next periodic wake probes successfully and is
      // caught up — the on-device repro logged
      // 'up to date (lastSync=852 tip=852)' while the banner stayed on screen.
      setProbeTip(600);
      await buildEngine().trySync();

      expect(recoveredCalls, 1,
          reason: 'the idle wake must signal recovery so the host clears '
              'the banner');
    });

    test('a successful scan signals recovery', () async {
      wallet.lastSync = 599;

      await buildEngine().trySync();

      expect(completedWith, true);
      expect(recoveredCalls, 1,
          reason: 'a completed sync clears the banner (D8 contract)');
    });

    test('a live monitor wake signals recovery', () async {
      wallet.lastSync = 600;
      final engine = buildEngine();
      // A monitor in this isolate holds a fresh scan-session: the wake
      // one-shot is skipped, but the subscription is a live round-trip.
      wallet.lock = FrigateScanLock(pid: engine.pid, beat: DateTime.now());

      await engine.trySync();

      expect(probeCalls, 0, reason: 'monitor live, wake scan skipped');
      expect(recoveredCalls, 1,
          reason: 'a live monitor subscription proves frigate is reachable');
    });
  });

  group('chain-consistency (probe genesis vs wallet network)', () {
    test(
        'probe on a foreign chain -> no scan, explicit banner, checkpoint untouched',
        () async {
      wallet.lastSync = 599;
      settings.probeNetwork = Network.mainnet; // fake wallet is signet
      setProbeTip(600); // rebuild the probe result on the foreign chain

      await buildEngine().trySync();

      expect(probeCalls, 1);
      expect(scanCalls, 0,
          reason: 'a backend indexing another chain must never be scanned');
      expect(watchCalls, 0, reason: 'no subscribe -> no watch-set disclosure');
      expect(wallet.disclosures, isEmpty,
          reason: 'no subscribe -> no disclosure record');
      expect(wallet.savedHeights, isEmpty,
          reason: 'checkpoint must not advance onto a foreign chain');
      expect(banners, isNotEmpty,
          reason:
              'the wallet must tell the user the backend is on another chain');
      expect(banners.single, contains('chain'),
          reason: 'explicit mismatch message, not a generic offline note');
    });
  });

  group('scan-session lock (D2)', () {
    test('stale lock at wake is cleared and the scan resumes from lastSync',
        () async {
      wallet.lastSync = 599;
      wallet.lock = FrigateScanLock(
        pid: 999999,
        beat: DateTime.now().subtract(const Duration(minutes: 30)),
      );

      await buildEngine().trySync();

      expect(wallet.lock, isNull, reason: 'dead lock cleared on wake');
      expect(scanCalls, 1);
      expect(scanCallsWith.single.fromHeight, 600,
          reason: 'resume from last Confirmed, not a history re-sweep');
    });
  });

  group('frigate-exclusive backend (owner ruling 2026-11-12)', () {
    test('backend blindbit (or unset) with frigate url set -> probe never runs',
        () async {
      wallet.lastSync = 599;
      settings.backend = frigateBackendBlindbit;

      await buildEngine().trySync();

      expect(probeCalls, 0, reason: 'frigate path never entered');
      expect(chainHeightCalls, 1, reason: 'blindbit wake logic used instead');
      expect(networkCheckCalls, 1);
      expect(scanCalls, 0,
          reason: 'blindbit scan needs the wallet object, absent in tests');
    });

    test('backend frigate + no url -> explicit idle, blindbit never consulted',
        () async {
      wallet.lastSync = 599;
      settings.frigateUrl = null;

      await buildEngine().trySync();

      expect(probeCalls, 0);
      expect(chainHeightCalls, 0,
          reason: 'the user selected frigate: a blindbit scan (different '
              'third party, different disclosure) is never a fallback');
      expect(networkCheckCalls, 0,
          reason: 'no blindbit wake logic may run either');
      expect(scanCalls, 0);
      expect(watchCalls, 0);
      expect(wallet.disclosures, isEmpty);
      expect(wallet.savedHeights, isEmpty,
          reason: 'checkpoint untouched in the explicit idle state');
      expect(wallet.lock, isNull);
      expect(banners, [frigateNoUrlMsg],
          reason: 'the idle state must be user-visible (D8 transient path)');
    });

    test('backend frigate + probe failure -> idle, blindbit never consulted',
        () async {
      wallet.lastSync = 599;
      setProbeTip(null); // probe will throw

      await buildEngine().trySync();

      expect(banners, [frigateOfflineMsg]);
      expect(scanCalls, 0);
      expect(watchCalls, 0);
      expect(wallet.disclosures, isEmpty);
      expect(chainHeightCalls, 0,
          reason: 'frigate-selected means frigate-exclusive: an unreachable '
              'server is an explicit idle, never a blindbit scan');
      expect(networkCheckCalls, 0);
      expect(wallet.lock, isNull);
      expect(wallet.savedHeights, isEmpty);

      // Auto-resume: the next wake (tip reachable again) scans normally.
      setProbeTip(600);
      await buildEngine().trySync();
      expect(scanCalls, 1);
      expect(scanCallsWith.single.fromHeight, 600);
    });
  });
}

class FakeWalletStore implements WalletStore {
  int? lastSync;
  final List<int> savedHeights = [];
  final List<Map<String, String>> disclosures = [];
  FrigateScanLock? lock;

  @override
  Future<bool> hasWallet() async => true;

  @override
  Future<SpWallet?> readWallet() async => null;

  @override
  Future<Network> readNetwork() async => Network.signet;

  @override
  Future<int?> readLastSync() async => lastSync;

  @override
  Future<void> saveLastSync(int? lastSync) async {
    savedHeights.add(lastSync!);
    this.lastSync = lastSync;
  }

  @override
  Future<DateTime?> readBirthday() async => null;

  @override
  Future<void> beginFrigateScan({required int pid}) async {
    lock = FrigateScanLock(pid: pid, beat: DateTime.now());
  }

  @override
  Future<void> touchFrigateScanBeat() async {}

  @override
  Future<void> endFrigateScan({int? tipHeight, String? tipHash}) async {
    lock = null;
  }

  @override
  Future<FrigateScanLock?> readFrigateScanLock() async => lock;

  @override
  Future<void> appendFrigateDisclosureRecord({
    required String url,
    required String visibility,
  }) async {
    disclosures.add({'url': url, 'visibility': visibility, 'date': 'test'});
  }
}

class FakeSettingsStore implements SettingsStore {
  String? blindbitUrl;
  String? frigateUrl;
  String? backend;
  String? visibility;
  FrigateTipProbe? probeTip;

  /// The chain the fake frigate backend follows; the fake wallet is signet.
  Network probeNetwork = Network.signet;

  @override
  Future<String?> getBlindbitUrl() async => blindbitUrl;

  @override
  Future<String?> getFrigateUrl() async => frigateUrl;

  @override
  Future<String?> getFrigateBackend() async => backend;

  @override
  Future<String?> getFrigateVisibility() async => visibility;

  @override
  Future<int?> getDustLimit() async => null;
}
