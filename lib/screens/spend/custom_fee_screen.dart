import 'dart:math' as math;

import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/data/enums/selected_fee.dart';
import 'package:danawallet/generated/rust/api/structs/input_selection.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/spend/ready_to_send.dart';
import 'package:danawallet/states/display_preferences_state.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/utils/coin_selection.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CustomFeeScreen extends StatefulWidget {
  final Recipient recipient;
  final Bip353Address? providedBip353;
  const CustomFeeScreen(
      {super.key, required this.recipient, this.providedBip353});

  @override
  State<CustomFeeScreen> createState() => _CustomFeeScreenState();
}

class _CustomFeeScreenState extends State<CustomFeeScreen> {
  static const int _minFeeRate = 1;
  static const int _maxFeeRate = 512;

  int _selectedFeeRate = _minFeeRate; // Default to 1 sat/vB
  double _sliderValue = 0.0; // slider position in [0, 1]
  FeeOptions? _options;
  InputSelection? _chosen;
  bool _isLoadingFees = true;
  String? _errorMessage;

  // The slider position is mapped to the fee rate logarithmically, so that
  // low rates (where precision matters most) get more track space.
  double _feeRateToSlider(int feeRate) =>
      math.log(feeRate) / math.log(_maxFeeRate);

  int _sliderToFeeRate(double value) => math
      .pow(_maxFeeRate.toDouble(), value)
      .round()
      .clamp(_minFeeRate, _maxFeeRate);

  String _formatFeeRate(double feeRate) => feeRate
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');

  @override
  void initState() {
    super.initState();
    _sliderValue = _feeRateToSlider(_selectedFeeRate);
    _computeFeeOptions();
  }

  void _computeFeeOptions() async {
    final walletState = Provider.of<WalletState>(context, listen: false);

    try {
      // Clear any previous error
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }

      final options = await walletState.estimateFeeOptions(
          widget.recipient, _selectedFeeRate);

      if (mounted) {
        setState(() {
          _options = options;
          _chosen = _recommended(options);
          _isLoadingFees = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _options = null;
          _chosen = null;
          _isLoadingFees = false;
          // Check if it's an insufficient funds error
          if (e.toString().contains('Insufficient funds') ||
              e.toString().contains('funds available')) {
            _errorMessage =
                'Fee too high - exceeds available funds. Try a lower fee rate.';
          } else {
            _errorMessage = 'Failed to calculate fee: ${e.toString()}';
          }
        });
      }
    }
  }

  // The no-change option is recommended when its fee does not exceed the
  // exact-rate fee plus the estimated future cost of spending the change
  // output at the same rate (~58 vB for a taproot key-spend input).
  InputSelection _recommended(FeeOptions options) {
    final noChange = options.noChange;
    if (noChange == null) {
      return options.exact;
    }
    final futureChangeCost = BigInt.from(58 * _selectedFeeRate);
    if (noChange.fee.field0 <= options.exact.fee.field0 + futureChangeCost) {
      return noChange;
    }
    return options.exact;
  }

  Future<void> onContinue() async {
    final chosen = _chosen;
    if (chosen == null) return;

    final walletState = Provider.of<WalletState>(context, listen: false);

    final unsignedTx = await walletState.createUnsignedTxFromSelection(
        widget.recipient, chosen);

    // update the send amount to the actual sent amount (can be different e.g. dust)
    final updatedRecipient = Recipient(
      paymentCode: widget.recipient.paymentCode,
      amount: unsignedTx.getSendAmount(),
    );

    if (mounted) {
      goToScreen(
          context,
          ReadyToSendScreen(
            recipient: updatedRecipient,
            providedBip353: widget.providedBip353,
            fee: SelectedFee.custom,
            unsignedTx: unsignedTx,
          ));
    }
  }

  Widget _optionCard(
    InputSelection selection, {
    required bool isNoChange,
    required bool recommended,
    required FiatExchangeRateState exchangeRate,
    required DisplayPreferencesState displayPreference,
  }) {
    final bitcoinUnit = displayPreference.amountDisplayUnit;
    final feeText =
        '${selection.fee.display(bitcoinUnit)} (${exchangeRate.displayFiat(selection.fee, displayPreference.fiatCurrency)})';

    final String title;
    final String subtitle;
    if (isNoChange) {
      title = 'No change output';
      subtitle =
          'Actual rate: ${_formatFeeRate(selection.actualFeeRate)} sat/vB. '
          'The remainder goes to the fee instead of a change output you would pay to spend later.';
    } else {
      title = 'Exact $_selectedFeeRate sat/vB';
      subtitle =
          'Returns ${selection.change.display(bitcoinUnit)} as change (a fee applies when spending it later).';
    }

    return GestureDetector(
      onTap: () => setState(() => _chosen = selection),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Bitcoin.neutral1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: _chosen == selection ? Bitcoin.orange : Bitcoin.neutral3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<InputSelection>(
              value: selection,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            style: BitcoinTextStyle.body4(Bitcoin.black)),
                      ),
                      const Spacer(),
                      Text(feeText,
                          style: BitcoinTextStyle.body4(Bitcoin.black)),
                    ],
                  ),
                  if (recommended) ...[
                    const SizedBox(height: 2),
                    Text('recommended',
                        style: BitcoinTextStyle.body5(Bitcoin.orange)),
                  ],
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: BitcoinTextStyle.body5(Bitcoin.neutral7)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _singleOption(
      InputSelection selection,
      FiatExchangeRateState exchangeRate,
      DisplayPreferencesState displayPreference) {
    final bitcoinUnit = displayPreference.amountDisplayUnit;
    // when even the best rate-honoring selection has no change output, the
    // remainder goes to the fee and the actual rate overshoots the target
    final absorbedInFee = selection.change.field0 == BigInt.zero &&
        selection.actualFeeRate > _selectedFeeRate * 1.05;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Bitcoin.neutral1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Estimated Fee',
                style: BitcoinTextStyle.body4(Bitcoin.black),
              ),
              Text(
                selection.fee.display(bitcoinUnit),
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
                exchangeRate.displayFiat(
                    selection.fee, displayPreference.fiatCurrency),
                style: BitcoinTextStyle.body5(Bitcoin.neutral7),
              ),
            ],
          ),
          if (absorbedInFee) ...[
            const SizedBox(height: 8),
            Text(
              'No change output is created; the remainder goes to the fee (actual rate: ${_formatFeeRate(selection.actualFeeRate)} sat/vB). '
              'This can be cheaper than creating and spending a change output later.',
              style: BitcoinTextStyle.body5(Bitcoin.neutral7),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate =
        Provider.of<FiatExchangeRateState>(context, listen: false);
    final displayPreference =
        Provider.of<DisplayPreferencesState>(context, listen: false);

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
                  min: 0,
                  max: 1,
                  onChanged: (double value) {
                    // only update the displayed rate while dragging;
                    // fees are recomputed on release
                    final newFeeRate = _sliderToFeeRate(value);
                    setState(() {
                      _sliderValue = value;
                      if (newFeeRate != _selectedFeeRate) {
                        _selectedFeeRate = newFeeRate;
                        // the fee options are for the previous rate
                        _isLoadingFees = true;
                      }
                    });
                  },
                  onChangeEnd: (double value) {
                    setState(() {
                      _isLoadingFees = true;
                    });
                    _computeFeeOptions();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          // Error message, loading indicator, or fee options
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Bitcoin.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Bitcoin.red.withValues(alpha: 0.3)),
              ),
              child: Column(
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
              ),
            )
          else if (_isLoadingFees || _options == null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Bitcoin.neutral1,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Loading...',
                style: BitcoinTextStyle.body4(Bitcoin.black),
              ),
            )
          else if (_options!.noChange != null)
            RadioGroup<InputSelection>(
              groupValue: _chosen,
              onChanged: (value) => setState(() => _chosen = value),
              child: Column(
                children: [
                  _optionCard(
                    _options!.noChange!,
                    isNoChange: true,
                    recommended: _recommended(_options!) == _options!.noChange,
                    exchangeRate: exchangeRate,
                    displayPreference: displayPreference,
                  ),
                  const SizedBox(height: 8),
                  _optionCard(
                    _options!.exact,
                    isNoChange: false,
                    recommended: _recommended(_options!) == _options!.exact,
                    exchangeRate: exchangeRate,
                    displayPreference: displayPreference,
                  ),
                ],
              ),
            )
          else
            _singleOption(_options!.exact, exchangeRate, displayPreference),
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
