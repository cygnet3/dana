import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/exceptions.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/bip39.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/screens/onboarding/choose_network.dart';
import 'package:danawallet/screens/onboarding/register_dana_address.dart';
import 'package:danawallet/screens/onboarding/onboarding_skeleton.dart';
import 'package:danawallet/screens/onboarding/recovery/seed_phrase.dart';
import 'package:danawallet/services/backup_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/scan_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button_outlined.dart';
import 'package:danawallet/widgets/info_widget.dart';
import 'package:danawallet/widgets/pin_guard.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  Future<void> onRestoreFile(BuildContext context) async {
    try {
      final walletState = Provider.of<WalletState>(context, listen: false);
      final chainState = Provider.of<ChainState>(context, listen: false);
      final contactsState = Provider.of<ContactsState>(context, listen: false);
      final scanProgress =
          Provider.of<ScanProgressNotifier>(context, listen: false);
      final encryptedBackup = await BackupService.getEncryptedBackupFromFile();

      if (encryptedBackup != null) {
        final controller = TextEditingController();

        final password = await showInputAlertDialog(
            controller,
            TextInputType.text,
            'Backup password',
            'provide password for backup',
            showReset: false);

        if (password is String) {
          await BackupService.restoreFromEncryptedBackup(
              encryptedBackup, password);

          await walletState.initialize();
          final network = walletState.network;
          final blindbitUrl =
              await SettingsRepository.instance.getBlindbitUrl() ??
                  network.defaultBlindbitUrl;
          chainState.initialize(network);

          // we can safely ignore the result of connecting, since we get the birthday from the backup
          await chainState.connect(blindbitUrl);

          chainState.startSyncService(walletState, scanProgress, true);

          final goToDanaAddressSetup =
              await walletState.checkDanaAddressRegistrationNeeded();

          // initialize contacts state using restored wallet state
          contactsState.initialize(
              walletState.receivePaymentCode, walletState.danaAddress);

          if (context.mounted) {
            Widget nextScreen = goToDanaAddressSetup
                ? const RegisterDanaAddressScreen()
                : const PinGuard();
            Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => nextScreen),
                (Route<dynamic> route) => false);
          }
        }
      }
    } catch (e) {
      if (e is InvalidNetworkException) {
        displayWarning("Backup file is for a different network");
      } else {
        displayWarning("restore failed, wrong password?");
      }
    }
  }

  Future<void> onCreateNewWallet(BuildContext context) async {
    ApiNetwork network;
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
    final scanProgress =
        Provider.of<ScanProgressNotifier>(context, listen: false);

    final blindbitUrl = network.defaultBlindbitUrl;

    chainState.initialize(network);
    final connected = await chainState.connect(blindbitUrl);

    // we *must* be connected to get the wallet birthday
    if (connected) {
      chainState.startSyncService(walletState, scanProgress, false);
      await walletState.createNewWallet(network);

      // initialize contacts state with the user's payment code
      contactsState.initialize(walletState.receivePaymentCode, null);
      if (network == ApiNetwork.regtest && context.mounted) {
        // for regtest we bypass the dana address setup screen
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const PinGuard()),
            (Route<dynamic> route) => false);
      } else {
        if (context.mounted) {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (context) => const RegisterDanaAddressScreen()),
              (Route<dynamic> route) => false);
        }
      }
    } else {
      displayWarning("Unable to create a new wallet; internet access required");
    }
  }

  Future<void> onRestoreMnemonic(BuildContext context) async {
    ApiNetwork network;
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
        if (isDevEnv)
          FooterButtonOutlined(
              title: 'Restore (file backup)',
              onPressed: () => onRestoreFile(context)),
        if (isDevEnv)
          const SizedBox(
            height: 15,
          ),
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
