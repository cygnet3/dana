import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/bip39.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/home/home.dart';
import 'package:danawallet/screens/onboarding/choose_network.dart';
import 'package:danawallet/screens/onboarding/notification_permission_screen.dart';
import 'package:danawallet/screens/onboarding/register_dana_address.dart';
import 'package:danawallet/screens/onboarding/onboarding_skeleton.dart';
import 'package:danawallet/screens/onboarding/recovery/seed_phrase.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/services/sync_orchestrator.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button_outlined.dart';
import 'package:danawallet/widgets/info_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  Future<void> onCreateNewWallet(BuildContext context) async {
    Network network;
    // in dev environment, allow user to choose network
    if (isDevEnv) {
      network = await Navigator.push(context,
          MaterialPageRoute(builder: (context) => const ChooseNetworkScreen()));
    } else {
      // Get network from flavor
      network = getNetworkForFlavor;
    }

    if (!context.mounted) {
      return;
    }

    final walletState = Provider.of<WalletState>(context, listen: false);
    final chainState = Provider.of<ChainState>(context, listen: false);
    final contactsState = Provider.of<ContactsState>(context, listen: false);
    final orchestrator = Provider.of<SyncOrchestrator>(context, listen: false);

    final blindbitUrl = network.defaultBlindbitUrl;

    chainState.initialize(network);
    final connected = await chainState.connect(blindbitUrl);

    // if we are connected, get the current block height
    // if we're not connected, we'll fetch the block height later in the chain sync serivce
    int? currentTip;
    if (connected) {
      currentTip = chainState.tip;
    }

    final goToDanaAddressSetup = connected && network != Network.regtest;

    await walletState.createNewWallet(network, currentTip);

    // initialize contacts state with the user's payment code
    contactsState.initialize(walletState.receivePaymentCode, null);

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

    // clear path (don't allow users to go back to registration screen by pressing 'back')
    Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => nextScreen),
        (Route<dynamic> route) => false);
  }

  Future<void> onRestoreMnemonic(BuildContext context) async {
    Network network;
    // in dev environment, allow user to choose network
    if (isDevEnv) {
      network = await Navigator.push(context,
          MaterialPageRoute(builder: (context) => const ChooseNetworkScreen()));
    } else {
      // Get network from flavor
      network = getNetworkForFlavor;
    }

    if (!context.mounted) {
      return;
    }

    // load bip39 words
    final bip39Words = getEnglishWordlist();

    // go to input seed phrase screen
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => SeedPhraseScreen(
                  bip39Words: bip39Words,
                  network: network,
                )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    var autoSizeGroup = AutoSizeGroup();
    final body = Column(
      children: [
        Image(
          width: Adaptive.h(18),
          image: const AssetImage(
            "assets/icons/dana_outline.png",
          ),
          color: Bitcoin.black,
        ),
        SizedBox(
          height: Adaptive.h(1),
        ),
        Expanded(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            InfoWidget(
                iconPath: "assets/icons/rocket.svg",
                title: "Effortless donations",
                text: "Start receiving donations within seconds!",
                group: autoSizeGroup),
            InfoWidget(
                iconPath: "assets/icons/hidden.svg",
                title: "Privacy by default",
                text:
                    "Bitcoin donations needed servers & intimidating infrastructure. Not anymore!",
                group: autoSizeGroup),
            InfoWidget(
                iconPath: "assets/icons/address-book.svg",
                title: "Email-like experience",
                text: "Send or receive bitcoin as if sending an email!",
                group: autoSizeGroup),
            const SizedBox(),
            const SizedBox(),
          ],
        ))
      ],
    );

    final footer = Column(
      children: [
        FooterButtonOutlined(
            title: 'Restore', onPressed: () => onRestoreMnemonic(context)),
        const SizedBox(
          height: 15,
        ),
        FooterButton(
            title: 'Create new wallet',
            onPressed: () => onCreateNewWallet(context)),
      ],
    );

    return OnboardingSkeleton(body: body, footer: footer);
  }
}
