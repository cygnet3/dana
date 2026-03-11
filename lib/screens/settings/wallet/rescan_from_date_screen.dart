import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Screen for rescanning the blockchain from a selected date.
/// Resets the scan position without changing the wallet birthday.
class RescanFromDateScreen extends StatefulWidget {
  const RescanFromDateScreen({super.key});

  @override
  State<RescanFromDateScreen> createState() => _RescanFromDateScreenState();
}

class _RescanFromDateScreenState extends State<RescanFromDateScreen> {
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
      final date = DateTime.utc(
          _selectedDate.year, _selectedDate.month, _selectedDate.day, 1);

      final height = await chainState.getBlockHeightFromDate(date);
      // First interrupt a sync if any
      await chainState.interruptSyncService();
      await walletState.resetToScanHeight(height);
      await chainState.requestSync();

      if (mounted) {
        displayNotification("Rescanning from selected date");
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        displayWarning("Failed to start rescan: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletState = Provider.of<WalletState>(context, listen: false);

    final subtitle = AutoSizeText(
      "Select a date to rescan the blockchain from. To rescan from before your wallet birthday, change your birthday first.",
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
              firstDate: walletState.birthday,
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
      title: "Rescan from date",
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
