import 'dart:async';

import 'package:danawallet/generated/rust/api/structs/frigate_scan_outcome.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/structs/state_update.dart';
import 'package:danawallet/generated/rust/api/wallet.dart' show SpWallet;
import 'package:danawallet/generated/rust/api/wallet/frigate.dart'
    show WatchedOutput;
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/services/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase-2/3 acceptance: FrigateMonitor lifecycle (decision-record amendment
/// 2026-11-10, acceptance test b).
///
/// Drives the foreground-service monitor wiring end-to-end with in-memory
/// stores and counting fakes — no rust library, no network. The monitor is
/// the persistent subscription that delivers the phase-2 mempool tail while
/// the app runs; the wake-cycle one-shot stays the phase-1 catch-up.
void main() {
  late FakeWalletStore wallet;
  late FakeSettingsStore settings;
  int monitorStartCalls = 0;
  final monitorStartsWith = <int>[];
  int monitorStopCalls = 0;
  // Rust-side monitor liveness truth (`frigateMonitorRunning`); true = task
  // alive. Set to false to simulate a dead monitor task.
  bool monitorTaskAlive = true;
  int probeCalls = 0;
  int watchCalls = 0;
  int scanCalls = 0;
  final scanStartsWith = <int>[];

  SyncEngine buildEngine() => SyncEngine(
        onSyncStarted: (start, end) {},
        onSyncComplete: (_) {},
        onStateUpdated: (_) async {},
        walletRepository: wallet,
        settingsRepository: settings,
        frigateProbe: ({required url}) async {
          probeCalls++;
          return (600, 'deadbeef');
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
          scanStartsWith.add(fromHeight);
          return const FrigateScanOutcome_Completed();
        },
        frigateMonitorStart: (
            {required frigateUrl,
            required fromHeight,
            required dustLimit,
            required watchedOutputs}) async {
          monitorStartCalls++;
          monitorStartsWith.add(fromHeight);
          monitorTaskAlive = true;
        },
        frigateMonitorStop: () async {
          monitorStopCalls++;
          monitorTaskAlive = false;
        },
        frigateMonitorActive: () async => monitorTaskAlive,
        // no real periodic beat in tests: liveness is asserted on the session
        // state, not on timer scheduling
        monitorBeatInterval: null,
        resultStreamFn: () => const Stream<StateUpdate>.empty(),
      );

  setUp(() {
    wallet = FakeWalletStore();
    settings = FakeSettingsStore();
    monitorStartCalls = 0;
    monitorStartsWith.clear();
    monitorStopCalls = 0;
    monitorTaskAlive = true;
    probeCalls = 0;
    watchCalls = 0;
    scanCalls = 0;
    scanStartsWith.clear();
    settings.backend = frigateBackendFrigate;
    settings.frigateUrl = '192.168.1.44:50002';
    wallet.lastSync = 599;
  });

  group('monitor lifecycle (amendment acceptance test b)', () {
    test('subscription held while the app runs: started once, session held',
        () async {
      final engine = buildEngine();
      await engine.ensureFrigateMonitor();

      expect(monitorStartCalls, 1,
          reason: 'the monitor must be wired into the foreground service');
      expect(monitorStartsWith.single, 600,
          reason: 'monitor resumes from the checkpoint (lastSync+1)');
      expect(wallet.disclosures.single['url'], '192.168.1.44:50002',
          reason: 'a monitor subscribe is a subscribe (D7 disclosure)');
      expect(wallet.lock, isNotNull,
          reason: 'monitor holds the persisted scan-session (D2)');

      // app keeps running: repeated liveness checks never re-subscribe
      await engine.ensureFrigateMonitor();
      await engine.ensureFrigateMonitor();
      expect(monitorStartCalls, 1, reason: 'subscription is held, not polled');
    });

    test('clean drop on stop: connection closed, session state cleared',
        () async {
      final engine = buildEngine();
      await engine.ensureFrigateMonitor();

      await engine.stopFrigateMonitor();

      expect(monitorStopCalls, 1,
          reason: 'stopFrigateMonitor must abort the scanner task');
      expect(wallet.lock, isNull,
          reason: 'the scan-session must not outlive the monitor');
      expect(wallet.disclosures.length, 1);

      // restartable after a clean stop
      await engine.ensureFrigateMonitor();
      expect(monitorStartCalls, 2);
    });

    test('post-death recovery: dead monitor task is restarted from the '
        'checkpoint (no receipt lost to monitor downtime)', () async {
      final engine = buildEngine();
      await engine.ensureFrigateMonitor();
      expect(monitorStartCalls, 1);

      // the rust-side monitor task dies (connection loss / process kill)
      monitorTaskAlive = false;

      // next foreground-service liveness pass re-establishes the
      // subscription; its history sweep from the checkpoint re-discovers
      // anything the dead monitor missed
      await engine.ensureFrigateMonitor();

      expect(monitorStartCalls, 2,
          reason: 'a dead monitor must be restarted, not trusted');
      expect(monitorStartsWith.last, 600,
          reason: 'restart resumes from the last checkpoint');
      expect(wallet.lock, isNotNull, reason: 'session re-established');
    });

    test('wake is a no-op while the monitor is live (D3: no duplicate '
        'subscription, no wake-cycle re-disclosure)', () async {
      final engine = buildEngine();
      await engine.ensureFrigateMonitor();
      final disclosuresAtMonitorStart = wallet.disclosures.length;

      await engine.trySync();

      expect(scanCalls, 0,
          reason: 'the monitor covers the live tail; the wake one-shot '
              'must not re-subscribe on top of it');
      expect(probeCalls, 0);
      expect(watchCalls, 1,
          reason: 'exactly the monitor start watch-set collection — the '
              'wake adds no extra disclosure');
      expect(wallet.disclosures.length, disclosuresAtMonitorStart,
          reason: 'no extra disclosure for an idle wake');
    });

    test('monitor death with no monitor running: wake one-shot (phase 1) '
        'recovers receipts from the checkpoint', () async {
      // monitor never started in this isolate (e.g. service killed with the
      // process): the wake-cycle one-shot is the recovery path
      final engine = buildEngine();
      monitorTaskAlive = false;

      await engine.trySync();

      expect(scanCalls, 1);
      expect(scanStartsWith.single, 600,
          reason: 'phase-1 recovery scans from the last Confirmed boundary');
    });

    test('backend switch away from frigate stops a running monitor (D9)',
        () async {
      final engine = buildEngine();
      await engine.ensureFrigateMonitor();
      settings.backend = frigateBackendBlindbit;

      await engine.ensureFrigateMonitor();

      expect(monitorStopCalls, 1,
          reason: 'the subscription must not outlive the backend selection');
      expect(wallet.lock, isNull);
    });
  });
}

class FakeWalletStore implements WalletStore {
  int? lastSync;
  final List<int> savedHeights = [];
  final List<Map<String, String>> disclosures = [];
  FrigateScanLock? lock;
  int beatTouches = 0;

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
  Future<void> touchFrigateScanBeat() async {
    beatTouches++;
  }

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
  (int, String)? probeTip;

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
