import 'dart:io';

import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/screens/home/home.dart';
import 'package:danawallet/screens/onboarding/notification_permission_screen.dart';
import 'package:danawallet/screens/onboarding/register_dana_address.dart';
import 'package:danawallet/services/sync_orchestrator.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const String restoreBandwidthWarning =
    "The recovery process may require a lot of network usage. Please make sure you are connected to wifi before you continue.";

Future<void> openWalletAfterRestore(
    BuildContext context, Network network) async {
  final walletState = Provider.of<WalletState>(context, listen: false);
  final chainState = Provider.of<ChainState>(context, listen: false);
  final contactsState = Provider.of<ContactsState>(context, listen: false);
  final orchestrator = Provider.of<SyncOrchestrator>(context, listen: false);

  chainState.initialize(network);

  final connected = await chainState.connect(network.defaultBlindbitUrl);
  if (!connected && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Unable to connect to network. Wallet will sync when connection is restored.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  final goToDanaAddressSetup =
      await walletState.checkDanaAddressRegistrationNeeded();

  contactsState.initialize(
      walletState.receivePaymentCode, walletState.danaAddress);

  await orchestrator.start();

  if (!context.mounted) return;

  final Widget nextScreen;
  if (Platform.isAndroid) {
    nextScreen = NotificationPermissionScreen(
      goToDanaAddressSetup: goToDanaAddressSetup,
    );
  } else if (goToDanaAddressSetup) {
    nextScreen = const RegisterDanaAddressScreen();
  } else {
    nextScreen = const HomeScreen();
  }

  Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => nextScreen),
      (Route<dynamic> route) => false);
}
