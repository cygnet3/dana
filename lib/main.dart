import 'dart:io';

import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/frb_generated.dart';

import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/screens/onboarding/introduction.dart';
import 'package:danawallet/screens/onboarding/register_dana_address.dart';
import 'package:danawallet/services/app_info_service.dart';
import 'package:danawallet/services/logging_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/home_state.dart';
import 'package:danawallet/states/scan_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/pin_guard.dart';
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
  await LoggingService.create();

  if (Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final appInfo = AppInfoService(packageInfo: await PackageInfo.fromPlatform());

  // Initialize contacts database
  await DatabaseHelper.instance.database;
  final walletState = await WalletState.create();
  final scanNotifier = await ScanProgressNotifier.create();
  final chainState = ChainState();
  final contactsState = ContactsState();
  final fiatExchangeRate = await FiatExchangeRateState.create();

  // Try to update exchange rate, but don't crash if it fails
  try {
    await fiatExchangeRate.updateExchangeRate();
  } catch (e) {
    Logger().w('Failed to update exchange rate during startup: $e');
    // Continue with cached data or no data - UI will handle it
  }

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

    final connected = await chainState.connect(blindbitUrl);
    if (!connected) {
      Logger().w("Failed to connect");
      // Continue without chain sync - wallet still usable for local operations
      // UI will show appropriate "offline" state
    }

    chainState.startSyncService(walletState, scanNotifier, true);

    final addressRegistrationNeeded =
        await walletState.checkDanaAddressRegistrationNeeded();

    // initialize contacts with the 'you' contact
    contactsState.initialize(
        walletState.receivePaymentCode, walletState.danaAddress);

    if (addressRegistrationNeeded) {
      landingPage = const RegisterDanaAddressScreen();
    } else {
      landingPage = const PinGuard();
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
        ChangeNotifierProvider.value(value: scanNotifier),
        ChangeNotifierProvider.value(value: chainState),
        ChangeNotifierProvider.value(value: HomeState()),
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
          ),
          home: landingPage);
    });
  }
}

Future<void> precacheImages() async {
  await precacheSvgPicture("assets/icons/address-book.svg");
  await precacheSvgPicture("assets/icons/boxes.svg");
  await precacheSvgPicture("assets/icons/contact.svg");
  await precacheSvgPicture("assets/icons/hidden.svg");
  await precacheSvgPicture("assets/icons/rocket.svg");
  await precacheSvgPicture("assets/icons/rocket-large.svg");
  await precacheSvgPicture("assets/icons/sparkle.svg");
}

Future precacheSvgPicture(String svgPath) async {
  final logo = SvgAssetLoader(svgPath);
  await svg.cache.putIfAbsent(logo.cacheKey(null), () => logo.loadBytes(null));
}
