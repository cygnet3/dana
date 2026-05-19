import 'dart:io';

import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/frb_generated.dart';

import 'package:danawallet/main.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:danawallet/repositories/owned_outputs_repository.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/transactions_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/screens/home/home.dart' show HomeScreen;
import 'package:danawallet/screens/onboarding/register_dana_address.dart';
import 'package:danawallet/screens/onboarding/introduction.dart';
import 'package:danawallet/services/app_info_service.dart';
import 'package:danawallet/services/foreground_sync_service.dart';
import 'package:danawallet/services/logging_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/home_state.dart';
import 'package:danawallet/states/permission_state.dart';
import 'package:danawallet/states/sync_orchestrator.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await LoggingService.create();

  if (Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else if (Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
    ForegroundSyncService.instance.initialize();
  } else {
    Logger().e('Dana wallet is not supported on this platform');
    exit(1);
  }

  final appInfo = AppInfoService(packageInfo: await PackageInfo.fromPlatform());

  // Initialize database
  await DatabaseHelper.instance.database;

  // Migrate legacy SharedPreferences data to SQLite (for users upgrading from older app versions)
  final spWallet = await WalletRepository.instance.readWallet();

  if (spWallet != null) {
    await migrateOutputsFromSharedPreferences();
    await migrateTxHistoryFromSharedPreferences(spWallet.getChangeAddress());
  }

  // after database migration, enable foreign_keys pragma
  DatabaseHelper.instance.enableForeignKeysPragma();

  final walletState = await WalletState.create();
  final permissionState = await PermissionState.create();
  final syncProgress = await SyncProgressState.create();
  final chainState = ChainState();
  final contactsState = ContactsState();
  final fiatExchangeRate = await FiatExchangeRateState.create();
  SyncOrchestrator? syncOrchestratorRef;
  final SyncBackend syncBackend;
  if (Platform.isLinux) {
    syncBackend = LinuxSyncBackend(
      chainState: chainState,
      syncProgress: syncProgress,
      walletState: walletState,
    );
  } else if (Platform.isAndroid) {
    syncBackend = AndroidSyncBackend(
      chainState: chainState,
      permissionState: permissionState,
      syncProgress: syncProgress,
      walletState: walletState,
      onFatalError: () =>
          syncOrchestratorRef?.restart(fallbackMode: true) ?? Future.value(),
    );
  } else {
    Logger().e('Dana wallet is not supported on this platform');
    exit(1);
  }
  final syncOrchestrator = SyncOrchestrator(
    backend: syncBackend,
    permissionState: permissionState,
  );
  syncOrchestratorRef = syncOrchestrator;

  // Try to update exchange rate, but don't crash if it fails
  try {
    await fiatExchangeRate.updateExchangeRate();
  } catch (e) {
    Logger().w('Failed to update exchange rate during startup: $e');
    // Continue with no data - UI will handle it
  }

  await precacheImages();

  final bool walletLoaded;
  try {
    walletLoaded = await walletState.initialize();
  } catch (e) {
    // todo: show an error screen when wallet is present but fails to load
    rethrow;
  }

  // if a blindbit url is given, override the saved url
  const blindbitUrl = String.fromEnvironment("BLINDBIT_URL");
  if (blindbitUrl != '') {
    await SettingsRepository.instance.setBlindbitUrl(blindbitUrl);
  }

  Widget landingPage;
  if (walletLoaded) {
    final network = walletState.network;
    final blindbitUrl = await SettingsRepository.instance.getBlindbitUrl() ??
        network.defaultBlindbitUrl;

    chainState.initialize(network);

    // Continue without chain sync - wallet still usable for local operations
    final connected = await chainState.connect(blindbitUrl);
    if (!connected) {
      Logger().w("Failed to connect");
    }

    final addressRegistrationNeeded =
        await walletState.checkDanaAddressRegistrationNeeded();

    // initialize contacts with the 'you' contact
    contactsState.initialize(
        walletState.receivePaymentCode, walletState.danaAddress);

    if (addressRegistrationNeeded) {
      landingPage = const RegisterDanaAddressScreen();
    } else {
      landingPage = const HomeScreen();
    }
  } else {
    // no wallet is loaded, so we go to the introduction screen
    landingPage = const IntroductionScreen();
  }

  runApp(
    MultiProvider(
      providers: [
        // simple providers for static/immutable data
        Provider.value(value: appInfo),
        // providers for mutable data
        ChangeNotifierProvider.value(value: walletState),
        ChangeNotifierProvider.value(value: syncProgress),
        ChangeNotifierProvider.value(value: chainState),
        ChangeNotifierProvider.value(value: HomeState()),
        ChangeNotifierProvider.value(value: permissionState),
        ChangeNotifierProvider.value(value: fiatExchangeRate),
        ChangeNotifierProvider.value(value: contactsState),
        ChangeNotifierProvider.value(value: syncOrchestrator),
      ],
      child: SilentPaymentApp(landingPage: landingPage),
    ),
  );

  if (walletLoaded) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      syncOrchestrator.start();
    });
  }
}
