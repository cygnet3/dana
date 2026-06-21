import 'dart:async';
import 'dart:io';

import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/frb_generated.dart';

import 'package:danawallet/global_functions.dart';
import 'package:danawallet/services/foreground_sync_service.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:danawallet/repositories/owned_outputs_repository.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/transactions_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/screens/home/home.dart';
import 'package:danawallet/screens/onboarding/introduction.dart';
import 'package:danawallet/screens/onboarding/register_dana_address.dart';
import 'package:danawallet/services/app_info_service.dart';
import 'package:danawallet/services/logging_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/home_state.dart';
import 'package:danawallet/states/permission_state.dart';
import 'package:danawallet/services/sync_orchestrator.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  LoggingService.create();

  if (Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else if (Platform.isAndroid) {
    ForegroundSyncService.initialize();
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

  final walletState = WalletState.create();
  final permissionState = await PermissionState.create();
  final syncProgress = SyncProgressState.create();
  final chainState = ChainState();
  final contactsState = ContactsState();
  final fiatExchangeRate = await FiatExchangeRateState.create();

  final syncOrchestrator = SyncOrchestrator(
    chainState: chainState,
    syncProgress: syncProgress,
    walletState: walletState,
    permissionState: permissionState,
  );

  // fetch the exchange rate, but don't await the response
  fiatExchangeRate.updateExchangeRate();

  await precacheImages();

  final bool walletLoaded;
  try {
    walletLoaded = await walletState.initialize();
  } catch (e) {
    // todo: show an error screen when wallet is present but fails to load
    rethrow;
  }

  Widget landingPage;
  if (walletLoaded) {
    final network = walletState.network;
    final blindbitUrl = await SettingsRepository.instance.getBlindbitUrl() ??
        network.defaultBlindbitUrl;

    chainState.initialize(network);

    await chainState.connect(blindbitUrl);

    final addressRegistrationNeeded =
        await walletState.checkDanaAddressRegistrationNeeded();

    // initialize contacts with the 'you' contact
    contactsState.initialize(
        walletState.receivePaymentCode, walletState.danaAddress);

    syncOrchestrator.start();

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
        Provider.value(value: syncOrchestrator),
        // providers for mutable data
        ChangeNotifierProvider.value(value: walletState),
        ChangeNotifierProvider.value(value: syncProgress),
        ChangeNotifierProvider.value(value: chainState),
        ChangeNotifierProvider.value(value: HomeState()),
        ChangeNotifierProvider.value(value: permissionState),
        ChangeNotifierProvider.value(value: fiatExchangeRate),
        ChangeNotifierProvider.value(value: contactsState),
      ],
      child: SilentPaymentApp(landingPage: landingPage),
    ),
  );
}

class SilentPaymentApp extends StatelessWidget {
  final Widget landingPage;

  const SilentPaymentApp({
    super.key,
    required this.landingPage,
  });

  @override
  Widget build(BuildContext context) {
    return Sizer(builder: (context, orientation, screenType) {
      return MaterialApp(
          title: 'Dana wallet',
          navigatorKey: globalNavigatorKey,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: danaBlue),
            useMaterial3: true,
            fontFamily: 'Space Grotesk',
            // SatoshiSymbol provides the sat glyph (U+E006) via PUA fallback
            fontFamilyFallback: const [satFontFamily],
          ),
          home: landingPage);
    });
  }
}

Future<void> precacheImages() async {
  await precacheSvgPicture("assets/icons/rocket.svg");
  await precacheSvgPicture("assets/icons/address-book.svg");
  await precacheSvgPicture("assets/icons/hidden.svg");
}

Future precacheSvgPicture(String svgPath) async {
  final logo = SvgAssetLoader(svgPath);
  await svg.cache.putIfAbsent(logo.cacheKey(null), () => logo.loadBytes(null));
}
