import 'package:barcode_widget/barcode_widget.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button_outlined.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String danaAddressExplanationText = "This is your Dana address. "
    "Share this address with other Dana users, or any other wallet "
    "that supports BIP353.";
const String copyAddressText = "Copy Address";
const String showStaticAddressText = "Show static address";
const String copiedDanaToClipboard = "Copied Dana address to clipboard";
const String copiedStaticToClipboard = "Copied Static address to clipboard";

class UserOverviewScreen extends StatefulWidget {
  final Contact youContact;

  const UserOverviewScreen({super.key, required this.youContact});

  @override
  State<UserOverviewScreen> createState() => _UserOverviewScreenState();
}

class _UserOverviewScreenState extends State<UserOverviewScreen> {
  bool extended = false;

  @override
  Widget build(BuildContext context) {
    final paymentCode = widget.youContact.paymentCode;
    final danaAddress = widget.youContact.bip353Address;

    return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      widget.youContact.avatar(50),
      const SizedBox(height: 15),
      if (danaAddress != null) ...[
        Text(
          danaAddress.username,
          style: BitcoinTextStyle.title3(Bitcoin.black),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _copyToClipboard(
              context, danaAddress.toString(), copiedDanaToClipboard),
          child: danaAddress.asRichText(18.0),
        ),
        const SizedBox(height: 8),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(danaAddressExplanationText)),
        const SizedBox(height: 24),
        FooterButton(
            title: copyAddressText,
            onPressed: () => _copyToClipboard(
                context, danaAddress.toString(), copiedDanaToClipboard)),
        const SizedBox(height: 16),
        if (!extended)
          FooterButtonOutlined(
              title: showStaticAddressText,
              onPressed: () => setState(() {
                    extended = true;
                  })),
      ],
      const SizedBox(height: 20),
      if (danaAddress == null || extended)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _copyToClipboard(
                  context, paymentCode.encode(), copiedStaticToClipboard),
              child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Bitcoin.neutral2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      BarcodeWidget(
                        data: paymentCode.encode(),
                        barcode: Barcode.qrCode(),
                      ),
                      const SizedBox(height: 8),
                      addressAsRichText(paymentCode.encode(), 14.0),
                      Text(
                        'tap to copy',
                        style: BitcoinTextStyle.body5(Bitcoin.neutral5),
                      ),
                    ],
                  )),
            ),
          ],
        )
    ]);
  }
}

Future<void> _copyToClipboard(
    BuildContext context, String textToCopy, String message) async {
  await Clipboard.setData(ClipboardData(text: textToCopy));
  HapticFeedback.lightImpact();
  if (!context.mounted) return;
  Navigator.of(context).pop();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.check_circle, color: Bitcoin.white, size: 16),
          const SizedBox(width: 8),
          Text(message),
        ],
      ),
      backgroundColor: Bitcoin.green.withValues(alpha: 0.8),
      duration: const Duration(seconds: 2),
    ),
  );
}
