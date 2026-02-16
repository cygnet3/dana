import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/recipient_form.dart';
import 'package:danawallet/extensions/payment_code.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/screens/spend/transaction_sent.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:text_scroll/text_scroll.dart';

class ReadyToSendScreen extends StatefulWidget {
  const ReadyToSendScreen({super.key});

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
      final unsignedTx = RecipientForm().unsignedTx!;

      final txid = await walletState.signAndBroadcastUnsignedTx(unsignedTx);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (context) => TransactionSentScreen(
                      txid: txid,
                      network: walletState.network,
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
    RecipientForm form = RecipientForm();

    TextStyle displayRecipientStyle = BitcoinTextStyle.title5(Bitcoin.neutral8);

    String displayRecipient = form.recipient!.displayName;

    // format on-chain addresses nicely
    if (displayRecipient == form.recipient!.paymentCode) {
      displayRecipient = displayRecipient.chunked(
          context, displayRecipientStyle, 0.85);
    }

    String displayAmount = form.amount!.displayBtc();

    String displayArrivalTime = form.selectedFee!.toEstimatedTime;

    String displayEstimatedFee = form.unsignedTx!.getFeeAmount().displayBtc();

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
            child: TextScroll(right,
                mode: TextScrollMode.bouncing,
                delayBefore: const Duration(milliseconds: 1500),
                pauseOnBounce: const Duration(milliseconds: 1000),
                pauseBetween: const Duration(milliseconds: 1000),
                textAlign: TextAlign.end,
                style: BitcoinTextStyle.title5(Bitcoin.neutral8))),
      if (!scrolling)
        Expanded(
            child: Text(right,
                textAlign: TextAlign.end,
                style: BitcoinTextStyle.title5(Bitcoin.neutral8))),
    ],
  );
}
