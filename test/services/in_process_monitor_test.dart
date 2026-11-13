import 'dart:async';

import 'package:danawallet/constants.dart' show frigateOfflineMsg;
import 'package:danawallet/generated/rust/api/structs/frigate_scan_outcome.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/structs/state_update.dart';
import 'package:danawallet/generated/rust/api/wallet.dart' show SpWallet;
import 'package:danawallet/generated/rust/api/wallet/frigate.dart'
    show FrigateTipProbe, WatchedOutput;
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/services/in_process_sync_service.dart';
import 'package:danawallet/services/sync_engine.dart';
import 'package:danawallet/states/sync_offline_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// PARTIAL-B regression (owner ruling 2026-11-12, item 4): the in-process
/// fallback path must resolve the backend per startup cycle and start the
/// frigate monitor on a frigate resolution — it previously never started a
/// monitor at all. The engine is built with counting fakes, so no rust
/// library and no network are involved.
void main() {
  late FakeWalletStore wallet;
  late FakeSettingsStore settings;
  int monitorStartCalls = 0;
  int monitorStopCalls = 0;
  bool monitorTaskAlive = false;

  SyncEngine buildEngine({SyncOfflineState? syncOffline}) => SyncEngine(
        onSyncStarted: (start, end) {},
        onSyncComplete: (_) {},
        onStateUpdated: (_) async {},
        onTransientOffline: (message) => syncOffline?.setOffline(message),
        onRecovered: () => syncOffline?.clear(),
        walletRepository: wallet,
        settingsRepository: settings,
        frigateProbe: ({required url}) async => const FrigateTipProbe(
            tipHeight: 600, tipHash: 'deadbeef', network: Network.signet),
        watchedOutputsFn: () async => const <WatchedOutput>[],
        frigateScanFn: (
                {required frigateUrl,
                required fromHeight,
                required dustLimit,
                required watchedOutputs}) async =>
            const FrigateScanOutcome_Completed(),
        frigateMonitorStart: (
            {required frigateUrl,
            required fromHeight,
            required dustLimit,
            required watchedOutputs}) async {
          monitorStartCalls++;
          monitorTaskAlive = true;
        },
        frigateMonitorStop: () async {
          monitorStopCalls++;
          monitorTaskAlive = false;
        },
        frigateMonitorActive: () async => monitorTaskAlive,
        monitorBeatInterval: null,
        resultStreamFn: () => const Stream<StateUpdate>.empty(),
      );

  setUp(() {
    wallet = FakeWalletStore();
    settings = FakeSettingsStore();
    monitorStartCalls = 0;
    monitorStopCalls = 0;
    monitorTaskAlive = false;
    settings.backend = frigateBackendFrigate;
    settings.frigateUrl = '192.168.1.44:50002';
    wallet.lastSync = 599;
  });

  test('frigate resolution: in-process startup starts the monitor', () async {
    final service = InProcessSyncService.withEngine(buildEngine());

    // Ordered startup: the backend/monitor resolution completes before the
    // chain poller can fire any one-shot trySync.
    await service.start();

    expect(monitorStartCalls, 1,
        reason: 'PARTIAL-B: the in-process fallback path must start the '
            'frigate monitor when the backend resolves to frigate');
    expect(wallet.disclosures.single['url'], '192.168.1.44:50002',
        reason: 'a monitor subscribe is a subscribe (D7 disclosure)');
    expect(wallet.lock, isNotNull,
        reason: 'the monitor holds the persisted scan-session (D2)');
  });

  test('blindbit resolution: in-process startup never starts a monitor',
      () async {
    settings.backend = frigateBackendBlindbit;
    final service = InProcessSyncService.withEngine(buildEngine());

    await service.start();

    expect(monitorStartCalls, 0,
        reason: 'blindbit is the default: no frigate monitor (D9)');
    expect(wallet.lock, isNull);
  });

  test('t_find_banner_stale: a recovered wake clears the offline banner',
      () async {
    final syncOffline = SyncOfflineState();
    final service =
        InProcessSyncService.withEngine(buildEngine(syncOffline: syncOffline));

    // The offline window set the D8 transient banner...
    syncOffline.setOffline(frigateOfflineMsg);
    expect(syncOffline.message, frigateOfflineMsg);

    // ...then frigate came back: the wake probe round-trip succeeds and the
    // wallet is caught up (lastSync == tip) — exactly the on-device repro.
    wallet.lastSync = 600; // fake probe tip is 600
    await service.trySync();

    expect(syncOffline.message, isNull,
        reason: 'the banner must clear on the next successful frigate '
            'round-trip');
  });

  test('dispose drops the monitor subscription and the session', () async {
    final service = InProcessSyncService.withEngine(buildEngine());
    await service.start();
    expect(monitorStartCalls, 1);

    service.dispose();
    await Future<void>.delayed(Duration.zero); // let the unawaited stop run

    expect(monitorStopCalls, 1,
        reason: 'the in-process service must not leave a subscription behind');
    expect(wallet.lock, isNull,
        reason: 'the scan-session must not outlive the monitor');
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
