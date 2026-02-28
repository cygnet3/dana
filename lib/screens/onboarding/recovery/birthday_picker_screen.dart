import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:flutter/material.dart';

/// Screen for selecting the wallet creation date (birthday).
/// Returns the selected [DateTime] when user confirms, or null if user goes back.
class BirthdayPickerScreen extends StatefulWidget {
  const BirthdayPickerScreen({super.key});

  @override
  State<BirthdayPickerScreen> createState() => _BirthdayPickerScreenState();
}

class _BirthdayPickerScreenState extends State<BirthdayPickerScreen> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    // Use UTC to avoid timezone issues with calendar dates
    final now = DateTime.now().toUtc();
    _selectedDate = DateTime.utc(now.year, now.month, now.day);
  }

  void _onConfirm() {
    Navigator.of(context).pop(_selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = AutoSizeText(
      "Choose the date when your wallet was created. This will make restoration faster.",
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
      title: "Select wallet birthday",
      showBackButton: true,
      body: body,
      footer: FooterButton(title: "Continue", onPressed: _onConfirm),
    );
  }
}
