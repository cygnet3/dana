import 'dart:async';

import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/enums/amount_display_unit.dart';
import 'package:danawallet/data/enums/fiat_currency.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/extensions/payment_code.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/spend/fee_selection.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/display_preferences_state.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/currency_unit_toggle.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AmountSelectionScreen extends StatefulWidget {
  final String paymentCode;
  final Bip353Address? providedBip353;
  const AmountSelectionScreen(
      {super.key, required this.paymentCode, this.providedBip353});

  @override
  AmountSelectionScreenState createState() => AmountSelectionScreenState();
}

class AmountSelectionScreenState extends State<AmountSelectionScreen> {
  final TextEditingController amountController = TextEditingController();
  String? _amountErrorText;
  Amount? _parsedAmount; // always sats
  bool _isFiatSelected = false;

  @override
  void initState() {
    super.initState();
    amountController.addListener(_onAmountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<FiatExchangeRateState>().updateExchangeRates());
    });
  }

  @override
  void dispose() {
    amountController.removeListener(_onAmountChanged);
    amountController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    final availableBalance =
        Provider.of<WalletState>(context, listen: false).amount;
    final fiatCurrency =
        Provider.of<DisplayPreferencesState>(context, listen: false)
            .fiatCurrency;
    final fiatExchangeRate =
        Provider.of<FiatExchangeRateState>(context, listen: false);

    Amount? parsed;
    String? errorMessage;
    try {
      parsed = _parseAmount(
        amountController.text.trim(),
        isFiatSelected: _isFiatSelected,
        fiatCurrency: fiatCurrency,
        fiatExchangeRate: fiatExchangeRate,
      );
      if (parsed != null) {
        if (parsed > availableBalance) {
          errorMessage = 'Not enough available funds';
        } else if (parsed < Amount(field0: BigInt.from(defaultDustLimit))) {
          errorMessage = 'Please send at least $defaultDustLimit sats';
        }
      }
    } on FormatException catch (e) {
      errorMessage = 'Invalid amount: ${e.message}';
    }
    setState(() {
      _parsedAmount = parsed;
      _amountErrorText = errorMessage;
    });
  }

  /// Parses [text] into sats. Returns null if empty.
  /// Throws [FormatException] if the input cannot be parsed.
  Amount? _parseAmount(
    String text, {
    required bool isFiatSelected,
    required FiatCurrency fiatCurrency,
    required FiatExchangeRateState fiatExchangeRate,
  }) {
    if (text.isEmpty) {
      return null;
    }

    if (isFiatSelected) {
      if (fiatExchangeRate.exchangeRateFor(fiatCurrency) == null) {
        throw const FormatException('Exchange rate unavailable');
      }
      final fiatAmount =
          AmountExtension.parseFiatInput(text, fiatCurrency.minorUnits());
      return fiatExchangeRate.fiatToSat(fiatAmount, fiatCurrency);
    }
    return AmountExtension.parseBtcInput(text);
  }

  String _amountHelperText(FiatCurrency currency) {
    if (!_isFiatSelected) {
      return 'Integer for sats, decimal (dot \'.\' separated) for BTC';
    }
    if (currency.minorUnits() == 0) {
      return 'Enter a whole amount in ${currency.displayName()}';
    }
    return 'Decimal (dot \'.\' separated) amount in ${currency.symbol()}';
  }

  String? _conversionHint({
    required bool hasFiatRate,
    required FiatExchangeRateState fiatExchangeRate,
    required FiatCurrency fiatCurrency,
    required AmountDisplayUnit bitcoinUnit,
  }) {
    if (!hasFiatRate) {
      return 'Conversion rate unavailable';
    }
    final amount = _parsedAmount;
    if (amount == null) {
      return null;
    }
    if (_isFiatSelected) {
      return '≈ ${amount.display(bitcoinUnit)}';
    }
    return '≈ ${fiatExchangeRate.displayFiat(amount, fiatCurrency)}';
  }

  void onContinue() {
    final amount = _parsedAmount;
    if (amount == null) {
      return;
    }

    final recipient = Recipient(
      paymentCode: widget.paymentCode,
      amount: amount,
    );

    goToScreen(
        context,
        FeeSelectionScreen(
            recipient: recipient, providedBip353: widget.providedBip353));
  }

  @override
  Widget build(BuildContext context) {
    final walletState = Provider.of<WalletState>(context, listen: false);
    final chainState = Provider.of<ChainState>(context, listen: false);
    final contacts = Provider.of<ContactsState>(context, listen: false);
    final displayPreferences =
        Provider.of<DisplayPreferencesState>(context, listen: false);
    final fiatExchangeRate = Provider.of<FiatExchangeRateState>(context);

    final fiatCurrency = displayPreferences.fiatCurrency;
    final bitcoinUnit = displayPreferences.amountDisplayUnit;
    final hasFiatRate = fiatExchangeRate.exchangeRateFor(fiatCurrency) != null;
    final conversionHint = _conversionHint(
      hasFiatRate: hasFiatRate,
      fiatExchangeRate: fiatExchangeRate,
      fiatCurrency: fiatCurrency,
      bitcoinUnit: bitcoinUnit,
    );

    final availableBalance = walletState.amount;
    int blocksToScan = 0;
    if (walletState.lastSync != null && chainState.available) {
      blocksToScan = chainState.tip - walletState.lastSync!;
    }

    final contact = contacts.getContactByPaymentCode(widget.paymentCode);

    TextStyle recipientTextStyle = BitcoinTextStyle.body4(Bitcoin.neutral7);

    // if name is available, use this
    String? recipientName = contact?.displayName;

    // if no contact is available, use the bip353 address
    recipientName ??= widget.providedBip353?.toString();

    // if no human-readable name available, format payment code nicely
    recipientName ??=
        widget.paymentCode.chunked(context, recipientTextStyle, 0.86);

    return ScreenSkeleton(
      showBackButton: true,
      title: 'Enter amount',
      body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Row(children: [
              SizedBox(
                  height: 50.0,
                  width: 50.0,
                  child: Image(
                    fit: BoxFit.contain,
                    image: const AssetImage("icons/3.0x/bitcoin_circle.png",
                        package: "bitcoin_ui"),
                    color: Bitcoin.orange,
                  )),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('To', style: BitcoinTextStyle.body5(Bitcoin.neutral7)),
                  Text(recipientName, style: recipientTextStyle),
                ],
              )
            ]),
            Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Amount',
                    style: BitcoinTextStyle.body5(Bitcoin.black),
                  ),
                ),
                const SizedBox(
                  height: 10.0,
                ),
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Enter an amount',
                    helperText: _amountHelperText(fiatCurrency),
                    errorText: _amountErrorText,
                    suffix: CurrencyUnitToggle(
                      isFiatSelected: _isFiatSelected,
                      fiatSymbol: fiatCurrency.symbol(),
                      enabled: hasFiatRate,
                      onTap: () => setState(() {
                        _isFiatSelected = !_isFiatSelected;
                        amountController.clear();
                      }),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
                if (conversionHint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        conversionHint,
                        style: BitcoinTextStyle.body5(Bitcoin.neutral7),
                      ),
                    ),
                  ),
                const SizedBox(
                  height: 10.0,
                ),
                Text(
                    'Available Balance: ${availableBalance.display(bitcoinUnit)}',
                    style: BitcoinTextStyle.body3(Bitcoin.black)
                        .apply(fontWeightDelta: 1)),
                if (blocksToScan != 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Warning: $blocksToScan block(s) to scan, balance might be inaccurate.',
                      style: BitcoinTextStyle.body5(Bitcoin.orange),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
            // just here for spacing, replace with fractionallysizedbox later
            const SizedBox(),
            const SizedBox(),
            const SizedBox(),
          ]),
      footer: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          FooterButton(
            title: 'Proceed to fee selection',
            enabled: _parsedAmount != null,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}
