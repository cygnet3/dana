import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/sync_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/icons/circular_icon.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const IconData pageIcon = Icons.warning_amber_rounded;
const Color pageColor = Colors.orange;

const String titleText = "Reset wallet to birthday";
const String infoText =
    "Are you sure you want to reset your wallet data? Only do this if you think your wallet data is corrupted, as you will lose valuable data like transaction history. This action cannot be undone.";
const String buttonText = "Reset wallet data";

class ConfirmWalletResetScreen extends StatelessWidget {
  const ConfirmWalletResetScreen({super.key});

  Future<void> onConfirmResetWallet(BuildContext context) async {
    final walletState = Provider.of<WalletState>(context, listen: false);
    final chainState = Provider.of<ChainState>(context, listen: false);

    // interrupt current sync
    await chainState.interruptSync();

    // reset wallet data
    await walletState.resetToBirthday();

    // go to home screen after resetting
    if (context.mounted) goToHomeScreen(context);
  }

  @override
  Widget build(BuildContext context) {
    const icon = CircularIcon(
        icon: Icon(
          pageIcon,
          color: Colors.white,
          size: 25,
        ),
        radius: 25,
        color: pageColor);

    final header = Text(
      titleText,
      style: BitcoinTextStyle.title3(Bitcoin.black),
    );

    final text = Text(
      infoText,
      style: BitcoinTextStyle.body3(Bitcoin.neutral8),
    );
    final items = Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        icon,
        header,
        text,
      ],
    );

    final body = Column(children: [
      Expanded(child: items),
      const Spacer(),
    ]);

    final footer = FooterButton(
      title: buttonText,
      onPressed: () => onConfirmResetWallet(context),
      color: pageColor,
    );

    return ScreenSkeleton(
      body: body,
      showBackButton: true,
      footer: footer,
    );
  }
}
