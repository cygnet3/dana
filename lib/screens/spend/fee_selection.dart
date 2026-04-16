import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/data/models/recommended_fee_model.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/data/enums/selected_fee.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/spend/ready_to_send.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/screens/spend/custom_fee_screen.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FeeSelectionScreen extends StatefulWidget {
  final Contact recipient;
  final ApiAmount amount;

  const FeeSelectionScreen(
      {super.key, required this.recipient, required this.amount});
  @override
  State<FeeSelectionScreen> createState() {
    return FeeSelectionScreenState();
  }
}

class FeeSelectionScreenState extends State<FeeSelectionScreen> {
  RecommendedFeeResponse? _currentFeeRates;
  SelectedFee _selected = SelectedFee.normal;
  final Map<SelectedFee, ApiAmount> _feeAmounts = {};

  @override
  void initState() {
    super.initState();
    _computeFeeAmounts();
  }

  Future<void> _computeFeeAmounts() async {
    final walletState = Provider.of<WalletState>(context, listen: false);
    final chainState = Provider.of<ChainState>(context, listen: false);

    // fetch fee rates from mempool
    final currentFeeRates = await chainState.getCurrentFeeRates();

    for (SelectedFee fee in [
      SelectedFee.fast,
      SelectedFee.normal,
      SelectedFee.slow
    ]) {
      final recipient = ApiRecipient(
          paymentCode: widget.recipient.paymentCode, amount: widget.amount);
      final feerate = fee.getFeeRate(currentFeeRates);
      final feeEstimationTx =
          await walletState.createUnsignedTxToThisRecipient(recipient, feerate);
      BigInt inputSum = BigInt.from(0);
      for (var (_, utxo) in feeEstimationTx.selectedUtxos) {
        inputSum += utxo.value.field0;
      }
      BigInt outputSum = BigInt.from(0);
      for (var recipient in feeEstimationTx.recipients) {
        outputSum += recipient.amount.field0;
      }
      _feeAmounts[fee] = ApiAmount(field0: inputSum - outputSum);
    }

    setState(() {
      _currentFeeRates = currentFeeRates;
    });
  }

  Future<void> onContinue() async {
    final walletState = Provider.of<WalletState>(context, listen: false);
    final changeAddress = walletState.changePaymentCode;

    final fee = _selected;

    final recipient = ApiRecipient(
        paymentCode: widget.recipient.paymentCode, amount: widget.amount);
    final feerate = fee.getFeeRate(_currentFeeRates!);

    final unsignedTx =
        await walletState.createUnsignedTxToThisRecipient(recipient, feerate);

    // update the send amount to the actual sent amount (can be different e.g. dust)
    // this should probably be done already on the amount screen?
    final finalAmount = unsignedTx.getSendAmount(changeAddress: changeAddress);

    if (mounted) {
      goToScreen(
          context,
          ReadyToSendScreen(
            recipient: widget.recipient,
            fee: _selected,
            amount: finalAmount,
            unsignedTx: unsignedTx,
          ));
    }
  }

  ListTile toListTile(SelectedFee fee, FiatExchangeRateState exchangeRate) {
    switch (fee) {
      case SelectedFee.fast:
      case SelectedFee.normal:
      case SelectedFee.slow:
        String subtitleBtc;
        String subtitleFiat;
        if (_currentFeeRates == null) {
          subtitleBtc = 'Loading...';
          subtitleFiat = 'Loading...';
        } else {
          final estimatedFee = _feeAmounts[fee];
          if (estimatedFee == null) {
            throw Exception('Fee amount not computed for $fee');
          }
          subtitleBtc = estimatedFee.displaySats();
          subtitleFiat = exchangeRate.displayFiat(estimatedFee);
        }

        return ListTile(
          title: Row(
            children: [
              Text(
                fee.toName,
                style: BitcoinTextStyle.body3(Bitcoin.black),
              ),
              const Spacer(),
              Text(fee.toEstimatedTime,
                  style: BitcoinTextStyle.body3(Bitcoin.black)),
            ],
          ),
          subtitle: Row(
            children: [
              Text(subtitleBtc,
                  style: BitcoinTextStyle.body5(Bitcoin.neutral7)),
              const Spacer(),
              Text(subtitleFiat,
                  style: BitcoinTextStyle.body5(Bitcoin.neutral7)),
            ],
          ),
          leading: Radio<SelectedFee>(
            value: fee,
          ),
          onTap: () {
            setState(() {
              _selected = fee;
            });
          },
        );
      case SelectedFee.custom:
        return ListTile(
          title: Text(
            SelectedFee.custom.toName,
            style: BitcoinTextStyle.body3(Bitcoin.black),
          ),
          trailing: const Image(
            image: AssetImage("icons/caret_right.png", package: "bitcoin_ui"),
          ),
          onTap: () {
            goToScreen(
                context,
                CustomFeeScreen(
                    recipient: widget.recipient, amount: widget.amount));
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate =
        Provider.of<FiatExchangeRateState>(context, listen: false);

    return ScreenSkeleton(
      showBackButton: true,
      title: 'Confirmation time',
      body: RadioGroup(
          groupValue: _selected,
          onChanged: (SelectedFee? value) {
            if (value != null) {
              setState(() {
                _selected = value;
              });
            }
          },
          child: Column(children: [
            const Divider(),
            toListTile(SelectedFee.fast, exchangeRate),
            const Divider(),
            toListTile(SelectedFee.normal, exchangeRate),
            const Divider(),
            toListTile(SelectedFee.slow, exchangeRate),
            const Divider(),
            if (isDevEnv) toListTile(SelectedFee.custom, exchangeRate),
            if (isDevEnv) const Divider(),
          ])),
      footer: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          const SizedBox(
            height: 10.0,
          ),
          FooterButton(
            title: 'Continue',
            onPressed: onContinue,
            enabled: _currentFeeRates != null,
          )
        ],
      ),
    );
  }
}
