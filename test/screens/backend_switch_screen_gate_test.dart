import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/wallet/frigate.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/screens/settings/network/frigate_settings_screen.dart';
import 'package:danawallet/services/backend_switch_gate.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// TICKET 2 (t_47fd1638): the backend-switch gate must be visible to the
/// USER, not just internal — a refused switch surfaces the v1 error in a
/// dialog and the wallet STAYS on the current backend (nothing persisted).
///
/// The chain tip is the single-producer tip of t_e67b63ae: the stub chain
/// state is seeded to 522 via the injected chainHeightFn. The frigate
/// backend under test is a local stub (the injected frigateTipProbeFn —
/// no network, no rust library).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mismatchMessage =
      'new backend seems inconsistent with existing history — check it '
      'follows the same chain and try again';

  final store = InMemorySharedPreferencesAsync.withData({});
  late ChainState chain;
  late SyncProgressState syncProgress;

  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance = store;
  });

  setUp(() async {
    await store.clear(
      const ClearPreferencesParameters(filter: PreferencesFilters()),
      const SharedPreferencesOptions(),
    );
    await SharedPreferencesAsync().setString('network', 'regtest');
    // A frigate url is already configured: the switch flow probes it.
    await SharedPreferencesAsync().setString('frigateurl', '127.0.0.1:50002');
    // Stub chain state: the single-producer tip sits at 522.
    chain = ChainState(
      chainHeightFn: ({required blindbitUrl}) async => 522,
      networkCheckFn: ({required blindbitUrl, required network}) async => true,
    )..initialize(Network.regtest);
    await chain.connect('http://stub-blindbit.invalid');
    syncProgress = SyncProgressState.forTesting();
  });

  Future<void> pumpScreen(WidgetTester tester,
      {required BackendSwitchGate gate}) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SyncProgressState>.value(value: syncProgress),
        ChangeNotifierProvider<ChainState>.value(value: chain),
      ],
      child: MaterialApp(home: FrigateSettingsScreen(switchGate: gate)),
    ));
    await tester.pumpAndSettle();

    // Drive the real switch flow: tap the tile, pick 'frigate'.
    await tester.tap(find.text('Sync backend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('frigate'));
    await tester.pumpAndSettle();
  }

  testWidgets('tip mismatch: error surfaced, wallet stays on blindbit',
      (tester) async {
    final gate = BackendSwitchGate(
      frigateTipProbeFn: ({required url}) async => const FrigateTipProbe(
          tipHeight: 523, tipHash: 'stub', network: Network.regtest),
      blindbitTipFn: ({required blindbitUrl}) async => 522,
      unconfirmedSpentCountFn: () async => 0,
    );

    await pumpScreen(tester, gate: gate);

    // The error reaches the user, verbatim.
    expect(find.text('Cannot switch backend'), findsOneWidget);
    expect(find.textContaining(mismatchMessage), findsOneWidget);

    // And the wallet stays put: nothing was persisted.
    expect(await SettingsRepository.instance.getFrigateBackend(),
        isNull); // still the unset (= blindbit) default
  });

  testWidgets('unconfirmed spends: switch blocked with a visible error',
      (tester) async {
    var probeCalled = false;
    final gate = BackendSwitchGate(
      frigateTipProbeFn: ({required url}) async {
        probeCalled = true;
        return const FrigateTipProbe(
            tipHeight: 522, tipHash: 'stub', network: Network.regtest);
      },
      blindbitTipFn: ({required blindbitUrl}) async => 522,
      unconfirmedSpentCountFn: () async => 1,
    );

    await pumpScreen(tester, gate: gate);

    expect(find.textContaining('unconfirmed'), findsOneWidget);
    expect(await SettingsRepository.instance.getFrigateBackend(), isNull);
    expect(probeCalled, isFalse);
  });

  testWidgets('exact tip match: switch succeeds and persists', (tester) async {
    final gate = BackendSwitchGate(
      frigateTipProbeFn: ({required url}) async => const FrigateTipProbe(
          tipHeight: 522, tipHash: 'stub', network: Network.regtest),
      blindbitTipFn: ({required blindbitUrl}) async => 522,
      unconfirmedSpentCountFn: () async => 0,
    );

    await pumpScreen(tester, gate: gate);

    expect(find.text('Cannot switch backend'), findsNothing);
    expect(await SettingsRepository.instance.getFrigateBackend(), 'frigate');
  });
}
