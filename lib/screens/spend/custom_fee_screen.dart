import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/recipient_form.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/data/models/recipient_form_filled.dart';
import 'package:danawallet/data/enums/selected_fee.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/screens/spend/ready_to_send.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CustomFeeScreen extends StatefulWidget {
  const CustomFeeScreen({super.key});

  @override
  State<CustomFeeScreen> createState() => _CustomFeeScreenState();
}

class _CustomFeeScreenState extends State<CustomFeeScreen> {
  int _selectedFeeRate = 1; // Default to 1 sat/vB
  double _sliderValue = 1.0; // Start at 1 sat/vB
  final Map<int, ApiAmount> _feeAmounts = {};
  bool _isLoadingFees = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _sliderValue = _selectedFeeRate.toDouble();
    _computeFeeAmounts();
  }

  void _computeFeeAmounts() async {
    final walletState = Provider.of<WalletState>(context, listen: false);
    RecipientForm form = RecipientForm();

    try {
      // Clear any previous error
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }

      // Compute fee for the currently selected rate
      form.selectedFee = SelectedFee.custom;
      form.customFeeRate = _selectedFeeRate;
      final filled = form.toFilled();
      final feeEstimationTx =
          await walletState.createUnsignedTxToThisRecipient(filled);
      BigInt inputSum = BigInt.from(0);
      for (var (_, utxo) in feeEstimationTx.selectedUtxos) {
        inputSum += utxo.amount.field0;
      }
      BigInt outputSum = BigInt.from(0);
      for (var recipient in feeEstimationTx.recipients) {
        outputSum += recipient.amount.field0;
      }
      _feeAmounts[_selectedFeeRate] = ApiAmount(field0: inputSum - outputSum);

      if (mounted) {
        setState(() {
          _isLoadingFees = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFees = false;
          // Check if it's an insufficient funds error
          if (e.toString().contains('Insufficient funds')) {
            _errorMessage =
                'Fee too high - exceeds available funds. Try a lower fee rate.';
          } else {
            _errorMessage = 'Failed to calculate fee: ${e.toString()}';
          }
        });
      }
    }
  }

  Future<void> onContinue() async {
    // Store the custom fee rate in the recipient form
    RecipientForm().customFeeRate = _selectedFeeRate;
    RecipientForm().selectedFee = SelectedFee.custom;

    final walletState = Provider.of<WalletState>(context, listen: false);
    final changeAddress = walletState.changePaymentCode;
    RecipientForm form = RecipientForm();

    RecipientFormFilled filled = form.toFilled();

    final unsignedTx =
        await walletState.createUnsignedTxToThisRecipient(filled);
    form.unsignedTx = unsignedTx;

    // update the send amount to the actual sent amount (can be different e.g. dust)
    form.amount = form.unsignedTx!.getSendAmount(changeAddress: changeAddress);

    if (mounted) {
      Navigator.push(context,
          MaterialPageRoute(builder: (context) => const ReadyToSendScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate =
        Provider.of<FiatExchangeRateState>(context, listen: false);

    return ScreenSkeleton(
      showBackButton: true,
      title: 'Custom Fee',
      body: Column(
        children: [
          const SizedBox(height: 20),
          // Fee rate display
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Bitcoin.neutral1,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '$_selectedFeeRate sat/vB',
                  style: BitcoinTextStyle.title3(Bitcoin.black),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          // Slider
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '1 sat/vB',
                    style: BitcoinTextStyle.body5(Bitcoin.neutral7),
                  ),
                  Text(
                    '512 sat/vB',
                    style: BitcoinTextStyle.body5(Bitcoin.neutral7),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Bitcoin.orange,
                  inactiveTrackColor: Bitcoin.neutral3,
                  thumbColor: Bitcoin.orange,
                  overlayColor: Bitcoin.orange.withValues(alpha: 0.1),
                  trackHeight: 4.0,
                ),
                child: Slider(
                  value: _sliderValue,
                  min: 1,
                  max: 512,
                  onChanged: (double value) {
                    final newFeeRate = value.round();
                    if (newFeeRate != _selectedFeeRate) {
                      setState(() {
                        _sliderValue = value;
                        _selectedFeeRate = newFeeRate;
                        _isLoadingFees = true;
                      });
                      // Recompute fees when the value changes
                      _computeFeeAmounts();
                    } else {
                      setState(() {
                        _sliderValue = value;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          // Error message or fee details
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _errorMessage != null
                  ? Bitcoin.red.withValues(alpha: 0.1)
                  : Bitcoin.neutral1,
              borderRadius: BorderRadius.circular(8),
              border: _errorMessage != null
                  ? Border.all(color: Bitcoin.red.withValues(alpha: 0.3))
                  : null,
            ),
            child: _errorMessage != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Bitcoin.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: BitcoinTextStyle.body4(Bitcoin.red),
                            ),
                          ),
                        ],
                      ),
                      if (_errorMessage!.contains('Fee too high'))
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            '💡 Tip: Start with a lower fee rate and gradually increase until you find the maximum your wallet can afford.',
                            style: BitcoinTextStyle.body5(Bitcoin.neutral6),
                          ),
                        ),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Estimated Fee',
                            style: BitcoinTextStyle.body4(Bitcoin.black),
                          ),
                          Text(
                            _isLoadingFees
                                ? 'Loading...'
                                : _feeAmounts[_selectedFeeRate]
                                        ?.displaySats() ??
                                    'N/A',
                            style: BitcoinTextStyle.body4(Bitcoin.black),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Fiat Equivalent',
                            style: BitcoinTextStyle.body5(Bitcoin.neutral7),
                          ),
                          Text(
                            _isLoadingFees
                                ? 'Loading...'
                                : exchangeRate.displayFiat(
                                    _feeAmounts[_selectedFeeRate]!),
                            style: BitcoinTextStyle.body5(Bitcoin.neutral7),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const Spacer(),
        ],
      ),
      footer: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          const SizedBox(height: 10.0),
          FooterButton(
            title: 'Continue',
            onPressed:
                (_isLoadingFees || _errorMessage != null) ? null : onContinue,
          ),
        ],
      ),
    );
  }
}
