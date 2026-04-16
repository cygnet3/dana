import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/screens/onboarding/introduction.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/home_state.dart';
import 'package:danawallet/states/sync_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/icons/circular_icon.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const Color pageColor = Colors.redAccent;

const String titleText = "Wipe wallet from this device";
const String info1Text =
    "This cannot be undone. Your recovery phrase and all other wallet data will be erased from this device.";
const String info2Text =
    "Please make sure you have backed up your seed phrase beforehand!";
const String buttonText = "Wipe wallet";

class ConfirmWalletDeletionScreen extends StatelessWidget {
  const ConfirmWalletDeletionScreen({super.key});

  Future<void> onConfirmWipeWallet(BuildContext context) async {
    final walletState = Provider.of<WalletState>(context, listen: false);
    final homeState = Provider.of<HomeState>(context, listen: false);
    final chainState = Provider.of<ChainState>(context, listen: false);
    final contacts = Provider.of<ContactsState>(context, listen: false);

    await chainState.reset();
    await walletState.reset();
    await SettingsRepository.instance.resetAll();
    contacts.reset();
    homeState.reset();

    if (context.mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (context) => const IntroductionScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    const icon = CircularIcon(
        icon: Icon(
          Icons.close,
          color: Colors.white,
          size: 20,
        ),
        radius: 25,
        color: pageColor);

    final header = Text(
      titleText,
      style: BitcoinTextStyle.title3(Bitcoin.black),
    );

    final text1 = Text(
      info1Text,
      style: BitcoinTextStyle.body3(Bitcoin.neutral8),
    );

    final text2 = Text(
      info2Text,
      style: BitcoinTextStyle.body3(Bitcoin.neutral8),
    );
    final items = Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        icon,
        header,
        text1,
        text2,
      ],
    );

    final body = Column(children: [
      Expanded(child: items),
      const Spacer(),
    ]);

    final footer = FooterButton(
      title: buttonText,
      onPressed: () => onConfirmWipeWallet(context),
      color: pageColor,
    );

    return ScreenSkeleton(
      body: body,
      showBackButton: true,
      footer: footer,
    );
  }
}
