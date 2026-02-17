import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/recipient_form.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/validate.dart';
import 'package:danawallet/screens/contacts/add_contact_sheet.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button_outlined.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class TransactionSentScreen extends StatefulWidget {
  final String txid;
  final Network network;

  const TransactionSentScreen({
    super.key,
    required this.txid,
    required this.network,
  });

  @override
  State<TransactionSentScreen> createState() => _TransactionSentScreenState();
}

class _TransactionSentScreenState extends State<TransactionSentScreen> {
  bool _isEligible = false;

  @override
  void initState() {
    super.initState();
    _checkEligibleToSaveContact();
  }

  void _checkEligibleToSaveContact() {
    final form = RecipientForm();
    final contacts = Provider.of<ContactsState>(context, listen: false);

    final recipient = form.recipient!;

    // only reusable payment codes (sp-addresses) are eligible
    final isReusable = isReusablePaymentCode(address: recipient.paymentCode);
    if (isReusable) {
      // We check by (reusable) payment codes instead of dana address.
      // This is important in the following case:
      // A user has 2 domains pointing to the same underlying payment code
      // aaa@domain and bbb@domain
      // If we already have aaa@domain in our contact list,
      // and we send to bbb@domain, we should still recognize that
      // we already have this recipient in our contact list.
      final knownPaymentCodes = contacts.getKnownPaymentCodes();

      final isInContacts = knownPaymentCodes.contains(recipient.paymentCode);
      if (!isInContacts) {
        setState(() {
          _isEligible = true;
        });
        return;
      }
    }
    setState(() {
      _isEligible = false;
    });
  }

  Future<void> _openAddContactSheet() async {
    final form = RecipientForm();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddContactSheet(
        initialDanaAddress: form.recipient!.bip353Address,
        initialPaymentCode: form.recipient!.paymentCode,
      ),
    );
    if (result == true) {
      setState(() {
        _isEligible = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String estimatedTime = RecipientForm().selectedFee!.toEstimatedTime;

    return ScreenSkeleton(
      showBackButton: false,
      body: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          // crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              height: 20.0,
            ),
            CircleAvatar(
              backgroundColor: Bitcoin.green,
              radius: 30, // Adjust size as needed
              child: Image(
                image: const AssetImage("icons/2.0x/share.png",
                    package: "bitcoin_ui"),
                color: Bitcoin.white,
                width: 30,
                height: 30,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(
              height: 20.0,
            ),
            Text(
              "Transaction sent",
              style: BitcoinTextStyle.title4(Bitcoin.black),
            ),
            const SizedBox(
              height: 10.0,
            ),
            Text(
              "Your transfer should be completed in $estimatedTime.",
              textAlign: TextAlign.center,
              style: BitcoinTextStyle.body3(Bitcoin.neutral7),
            ),
          ]),
      footer: Column(
        children: [
          if (widget.network != Network.regtest)
            FooterButtonOutlined(
              title: 'View in block explorer',
              onPressed: () async {
                try {
                  String baseUrl;
                  switch (widget.network) {
                    case Network.mainnet:
                      baseUrl = 'https://mempool.space';
                      break;
                    case Network.testnet3:
                    case Network.testnet4:
                      baseUrl = 'https://mempool.space/testnet';
                      break;
                    case Network.signet:
                      baseUrl = 'https://mempool.space/signet';
                      break;
                    case Network.regtest:
                      return; // Should not reach here due to if condition
                  }
                  final url = Uri.parse('$baseUrl/tx/${widget.txid}');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Unable to open block explorer'),
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to open block explorer: $e'),
                      ),
                    );
                  }
                }
              },
            ),
          if (widget.network != Network.regtest)
            const SizedBox(
              height: 10.0,
            ),
          if (_isEligible)
            FooterButtonOutlined(
              title: 'Add to contact',
              onPressed: _openAddContactSheet,
            ),
          if (_isEligible)
            const SizedBox(
              height: 10.0,
            ),
          FooterButton(
              title: 'Done',
              onPressed: () {
                Navigator.pop(context);
              })
        ],
      ),
    );
  }
}
