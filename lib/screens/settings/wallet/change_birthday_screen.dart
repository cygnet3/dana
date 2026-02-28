import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Screen for changing the wallet birthday date.
/// Updates the stored birthday and resets scan position to the corresponding block height.
class ChangeBirthdayScreen extends StatefulWidget {
  const ChangeBirthdayScreen({super.key});

  @override
  State<ChangeBirthdayScreen> createState() => _ChangeBirthdayScreenState();
}

class _ChangeBirthdayScreenState extends State<ChangeBirthdayScreen> {
  late DateTime _selectedDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final walletState = Provider.of<WalletState>(context, listen: false);
    _selectedDate = walletState.birthday;
  }

  Future<void> _onConfirm() async {
    setState(() => _isLoading = true);

    try {
      final walletState = Provider.of<WalletState>(context, listen: false);
      final chainState = Provider.of<ChainState>(context, listen: false);

      // Use 1am UTC to avoid edge issues at midnight
      final birthday = DateTime.utc(
          _selectedDate.year, _selectedDate.month, _selectedDate.day, 1);

      final height = await chainState.getBlockHeightFromDate(birthday);
      await walletState.updateBirthday(birthday);
      await walletState.resetToScanHeight(height);

      if (mounted) {
        displayNotification("Wallet birthday updated");
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        displayWarning("Failed to update birthday: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = AutoSizeText(
      "Select the date when your wallet was created. Scanning will restart from this date.",
      style: BitcoinTextStyle.body3(Bitcoin.neutral7).copyWith(
        fontFamily: 'Inter',
      ),
      textAlign: TextAlign.center,
      maxLines: 3,
    );

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: subtitle,
        ),
        Expanded(
          child: SingleChildScrollView(
            child: CalendarDatePicker(
              initialDate: _selectedDate,
              firstDate: minimumAllowedBirthday,
              lastDate: DateTime.now().toUtc(),
              currentDate: DateTime.now().toUtc(),
              onDateChanged: (date) {
                setState(() {
                  _selectedDate = date;
                });
              },
            ),
          ),
        ),
      ],
    );

    return ScreenSkeleton(
      title: "Change wallet birthday",
      showBackButton: true,
      body: body,
      footer: FooterButton(
        title: "Confirm",
        onPressed: _onConfirm,
        isLoading: _isLoading,
      ),
    );
  }
}
