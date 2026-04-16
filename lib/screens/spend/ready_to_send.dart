import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/enums/selected_fee.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/extensions/payment_code.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/generated/rust/api/structs/unsigned_transaction.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/screens/spend/transaction_sent.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/text/scrollable_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ReadyToSendScreen extends StatefulWidget {
  final Recipient recipient;
  final Bip353Address? providedBip353;
  final SelectedFee fee;
  final ApiSilentPaymentUnsignedTransaction unsignedTx;
  const ReadyToSendScreen(
      {super.key,
      required this.unsignedTx,
      required this.fee,
      required this.recipient,
      this.providedBip353});

  @override
  ReadyToSendScreenState createState() => ReadyToSendScreenState();
}

class ReadyToSendScreenState extends State<ReadyToSendScreen> {
  bool _isSending = false;
  String? _sendErrorText;

  Future<void> onPressSend() async {
    setState(() {
      _isSending = true;
      _sendErrorText = null;
    });

    try {
      final walletState = Provider.of<WalletState>(context, listen: false);

      final txid =
          await walletState.signAndBroadcastUnsignedTx(widget.unsignedTx);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (context) => TransactionSentScreen(
                      recipient: widget.recipient,
                      fee: widget.fee,
                      txid: txid,
                      network: walletState.network,
                      providedBip353: widget.providedBip353,
                    )),
            (Route<dynamic> route) => route.isFirst);
      }
    } catch (e) {
      setState(() {
        _isSending = false;
        _sendErrorText = exceptionToString(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = Provider.of<ContactsState>(context, listen: false);

    final contact =
        contacts.getContactByPaymentCode(widget.recipient.paymentCode);

    TextStyle displayRecipientStyle = BitcoinTextStyle.title5(Bitcoin.neutral7);

    // if name is available, use this
    String? displayRecipient = contact?.displayName;

    // if no contact is available, use the bip353 address
    displayRecipient ??= widget.providedBip353?.toString();

    // if no human-readable name available, format payment code nicely
    displayRecipient ??= widget.recipient.paymentCode
        .chunked(context, displayRecipientStyle, 0.85);

    String displayAmount = widget.recipient.amount.displayBtc();

    String displayArrivalTime = widget.fee.toEstimatedTime;

    String displayEstimatedFee = widget.unsignedTx.getFeeAmount().displayBtc();

    return ScreenSkeleton(
        showBackButton: true,
        title: 'Ready to send?',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              height: 50.0,
            ),
            entryRow('To', displayRecipient, true),
            const Divider(),
            entryRow('Amount', displayAmount, false),
            const Divider(),
            entryRow('Arrival time', displayArrivalTime, false),
            const Divider(),
            entryRow('Fee', displayEstimatedFee, false),
          ],
        ),
        footer: Column(
          children: [
            if (_sendErrorText != null) Text(_sendErrorText!),
            const SizedBox(
              height: 10.0,
            ),
            FooterButton(
              title: 'Send',
              onPressed: onPressSend,
              isLoading: _isSending,
            ),
          ],
        ));
  }
}

Widget entryRow(String left, String right, bool scrolling) {
  return Row(
    children: [
      Text(
        left,
        style: BitcoinTextStyle.title5(Bitcoin.neutral7),
      ),
      const SizedBox(width: 30),
      if (scrolling)
        Expanded(
            child: ScrollableText(
                text: right, style: BitcoinTextStyle.title5(Bitcoin.neutral8))),
      if (!scrolling)
        Expanded(
            child: Text(right,
                textAlign: TextAlign.end,
                style: BitcoinTextStyle.title5(Bitcoin.neutral8))),
    ],
  );
}
