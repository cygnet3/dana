import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/enums/warning_type.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/onboarding/recovery/birthday_picker_screen.dart';
import 'package:danawallet/screens/onboarding/recovery/restore_flow.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/loading_widget.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';

class DescriptorRestoreScreen extends StatefulWidget {
  final Network network;

  const DescriptorRestoreScreen({super.key, required this.network});

  @override
  State<DescriptorRestoreScreen> createState() =>
      _DescriptorRestoreScreenState();
}

class _DescriptorRestoreScreenState extends State<DescriptorRestoreScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _knowsBirthday = false;
  bool _isLoading = false;

  Future<void> onRestore(BuildContext context) async {
    final descriptor = _controller.text.trim();
    if (descriptor.isEmpty) {
      return;
    }

    try {
      final walletState = Provider.of<WalletState>(context, listen: false);

      DateTime? birthday;
      if (_knowsBirthday) {
        final pickedDate = await Navigator.push<DateTime>(
          context,
          MaterialPageRoute(
            builder: (context) => const BirthdayPickerScreen(),
          ),
        );
        if (!context.mounted) {
          return;
        }
        if (pickedDate == null) {
          return;
        }
        birthday =
            DateTime.utc(pickedDate.year, pickedDate.month, pickedDate.day, 1);
      }

      setState(() {
        _isLoading = true;
      });

      await walletState.restoreWalletFromDescriptor(
          widget.network, descriptor, birthday);
      if (!context.mounted) return;
      await openWalletAfterRestore(context, widget.network);
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _isLoading = false;
        });
        displayError("Restore failed", e);
      }
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    _controller.text = text.trim();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _onDescriptorChanged() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onDescriptorChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showWarningDialog(restoreBandwidthWarning, WarningType.info);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onDescriptorChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingWidget();
    }

    final subtitle = AutoSizeText(
      "Paste an sp() descriptor that includes the spend private key. This wallet will not have a recovery phrase.",
      style: BitcoinTextStyle.body3(Bitcoin.neutral7).copyWith(
        fontFamily: 'Inter',
      ),
      textAlign: TextAlign.center,
      maxLines: 5,
    );

    final body = SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: Adaptive.h(3),
              horizontal: Adaptive.w(2),
            ),
            child: subtitle,
          ),
          TextField(
            controller: _controller,
            minLines: 4,
            maxLines: 8,
            autocorrect: false,
            enableSuggestions: false,
            style: BitcoinTextStyle.body5(Bitcoin.neutral8).copyWith(
              fontFamily: 'Inter',
            ),
            decoration: InputDecoration(
              hintText: 'sp(...)',
              hintStyle: BitcoinTextStyle.body4(Bitcoin.neutral5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Bitcoin.neutral3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Bitcoin.neutral3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Bitcoin.neutral5),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste),
                color: Bitcoin.neutral6,
                onPressed: _paste,
              ),
            ),
          ),
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
      ),
    );

    final footer = FooterButton(
      title: "Import",
      enabled: _controller.text.trim().isNotEmpty,
      onPressed: () => onRestore(context),
    );

    return ScreenSkeleton(
      title: "Enter your descriptor",
      showBackButton: true,
      body: body,
      footer: footer,
    );
  }
}
