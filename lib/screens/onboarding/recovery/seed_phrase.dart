import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/enums/warning_type.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/onboarding/recovery/birthday_picker_screen.dart';
import 'package:danawallet/screens/onboarding/register_dana_address.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/scan_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/loading_widget.dart';
import 'package:danawallet/widgets/pills/mnemonic_input_pill_box.dart';
import 'package:danawallet/widgets/pin_guard.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';

const String bandwidthWarning =
    "The recovery process may require a lot of network usage. Please make sure you are connected to wifi before you continue.";

const int _mnemonicCount = 12;

class SeedPhraseScreen extends StatefulWidget {
  final List<String> bip39Words;
  final ApiNetwork network;
  const SeedPhraseScreen({
    super.key,
    required this.bip39Words,
    required this.network,
  });

  @override
  State<SeedPhraseScreen> createState() => SeedPhraseScreenState();
}

class SeedPhraseScreenState extends State<SeedPhraseScreen> {
  late List<TextEditingController> controllers;
  late List<FocusNode> focusNodes;
  late MnemonicInputPillBox pills;
  bool _knowsBirthday = false;
  bool _isLoading = false;

  Future<void> onRestore(BuildContext context) async {
    try {
      final mnemonic = pills.mnemonic;
      final walletState = Provider.of<WalletState>(context, listen: false);
      final chainState = Provider.of<ChainState>(context, listen: false);
      final contactsState = Provider.of<ContactsState>(context, listen: false);
      final scanProgress =
          Provider.of<ScanProgressNotifier>(context, listen: false);

      // Get birthday: navigate to picker if user knows it, else null
      DateTime? birthday;
      if (_knowsBirthday) {
        final pickedDate = await Navigator.push<DateTime>(
          context,
          MaterialPageRoute(
            builder: (context) => const BirthdayPickerScreen(),
          ),
        );
        if (!context.mounted) {
          return; // Context lost, abort restore
        }
        if (pickedDate == null) {
          return; // User pressed back, stay on seed phrase screen
        }
        // pickedDate is already in UTC from BirthdayPickerScreen
        // Use 1am UTC to avoid edge issues at midnight
        birthday = DateTime.utc(
            pickedDate.year, pickedDate.month, pickedDate.day, 1);
      }

      setState(() {
        _isLoading = true;
      });

      await walletState.restoreWallet(widget.network, mnemonic, birthday);

      chainState.initialize(widget.network);
      
      // Try to connect, but continue even if it fails (offline mode)
      final connected = await chainState.connect(widget.network.defaultBlindbitUrl);
      if (!connected) {
        // Connection failed, but continue anyway - sync will happen when network is available
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to connect to network. Wallet will sync when connection is restored.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }

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
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _isLoading = false;
        });
        displayError("Restore failed", e);
      }
    }
  }

  @override
  void initState() {
    super.initState();

    controllers = List.generate(_mnemonicCount, (i) => TextEditingController());
    focusNodes = List.generate(_mnemonicCount, (i) => FocusNode());
    pills = MnemonicInputPillBox(
      validWords: widget.bip39Words,
      controllers: controllers,
      focusNodes: focusNodes,
    );

    // add warning message about bandwidth after building
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showWarningDialog(bandwidthWarning, WarningType.info);
    });
  }

  @override
  void dispose() {
    for (int i = 0; i < _mnemonicCount; i++) {
      // dispose controllers and focusnodes
      controllers[i].dispose();
      focusNodes[i].dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingWidget();
    }

    final subtitle = AutoSizeText(
      "Enter your recovery phrase. Don't enter a recovery phrase that wasn't generated by Dana!",
      style: BitcoinTextStyle.body3(Bitcoin.neutral7).copyWith(
        fontFamily: 'Inter',
      ),
      textAlign: TextAlign.center,
      maxLines: 3,
    );

    final body = Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: Adaptive.h(3),
            horizontal: Adaptive.w(2),
          ),
          child: subtitle,
        ),
        Expanded(child: pills),
        Padding(
          padding: EdgeInsets.symmetric(vertical: Adaptive.h(1.5)),
          child: CheckboxListTile(
            value: _knowsBirthday,
            onChanged: (value) {
              setState(() {
                _knowsBirthday = value ?? false;
              });
            },
            title: Text(
              "I know when my wallet was created (birthday)",
              style: BitcoinTextStyle.body3(Bitcoin.neutral7).copyWith(
                fontFamily: 'Inter',
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );

    final footer =
        FooterButton(title: "Import", onPressed: () => onRestore(context));

    return ScreenSkeleton(
      title: "Enter your recovery phrase",
      showBackButton: true,
      body: body,
      footer: footer,
    );
  }
}
