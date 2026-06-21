import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/enums/amount_display_unit.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/recommended_fee_model.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/data/enums/selected_fee.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/spend/ready_to_send.dart';
import 'package:danawallet/states/display_preferences_state.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/screens/spend/custom_fee_screen.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FeeSelectionScreen extends StatefulWidget {
  final Recipient recipient;
  final Bip353Address? providedBip353;

  const FeeSelectionScreen(
      {super.key, required this.recipient, this.providedBip353});
  @override
  State<FeeSelectionScreen> createState() {
    return FeeSelectionScreenState();
  }
}

class FeeSelectionScreenState extends State<FeeSelectionScreen> {
  RecommendedFeeResponse? _currentFeeRates;
  SelectedFee _selected = SelectedFee.normal;
  final Map<SelectedFee, Amount> _feeAmounts = {};

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
      final feerate = fee.getFeeRate(currentFeeRates);
      final feeEstimationTx = await walletState.createUnsignedTxToThisRecipient(
          widget.recipient, feerate);
      BigInt inputSum = BigInt.from(0);
      for (var (_, utxo) in feeEstimationTx.selectedUtxos) {
        inputSum += utxo.value.field0;
      }
      BigInt outputSum = BigInt.from(0);
      for (var recipient in feeEstimationTx.recipients) {
        outputSum += recipient.amount.field0;
      }
      _feeAmounts[fee] = Amount(field0: inputSum - outputSum);
    }

    setState(() {
      _currentFeeRates = currentFeeRates;
    });
  }

  Future<void> onContinue() async {
    final walletState = Provider.of<WalletState>(context, listen: false);
    final changeCode = walletState.changePaymentCode;

    final feerate = _selected.getFeeRate(_currentFeeRates!);

    final unsignedTx = await walletState.createUnsignedTxToThisRecipient(
        widget.recipient, feerate);

    // update the send amount to the actual sent amount (can be different e.g. dust)
    final updatedRecipient = Recipient(
      paymentCode: widget.recipient.paymentCode,
      amount: unsignedTx.getSendAmount(changeCode: changeCode),
    );

    if (mounted) {
      goToScreen(
          context,
          ReadyToSendScreen(
            recipient: updatedRecipient,
            providedBip353: widget.providedBip353,
            fee: _selected,
            unsignedTx: unsignedTx,
          ));
    }
  }

  ListTile toListTile(SelectedFee fee, FiatExchangeRateState exchangeRate,
      AmountDisplayUnit bitcoinUnit) {
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
          subtitleBtc = estimatedFee.display(bitcoinUnit);
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
                  recipient: widget.recipient,
                  providedBip353: widget.providedBip353,
                ));
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate =
        Provider.of<FiatExchangeRateState>(context, listen: false);
    final displayPreference =
        Provider.of<DisplayPreferencesState>(context, listen: false);

    final bitcoinUnit = displayPreference.amountDisplayUnit;

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
            toListTile(SelectedFee.fast, exchangeRate, bitcoinUnit),
            const Divider(),
            toListTile(SelectedFee.normal, exchangeRate, bitcoinUnit),
            const Divider(),
            toListTile(SelectedFee.slow, exchangeRate, bitcoinUnit),
            const Divider(),
            if (isDevEnv)
              toListTile(SelectedFee.custom, exchangeRate, bitcoinUnit),
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
