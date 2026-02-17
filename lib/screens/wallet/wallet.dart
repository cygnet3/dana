import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/enums/warning_type.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/recorded_transaction.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/spend/choose_recipient.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/scan_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const String mainnetWarning =
    "You are currently on Mainnet. This means you are using real funds. Please note that this wallet is still considered experimental, so there may be some risks involved. Don't use funds that you are unwilling to lose. You have been warned.";

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  WalletScreenState createState() => WalletScreenState();
}

class WalletScreenState extends State<WalletScreen> {
  bool hideAmount = false;

  @override
  void initState() {
    super.initState();

    // if we are on mainnet, show a warning message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final walletState = Provider.of<WalletState>(context, listen: false);
      if (walletState.network == Network.mainnet) {
        showWarningDialog(mainnetWarning, WarningType.warn);
      }
    });
  }

  Widget buildScanProgress(double scanProgress) {
    return Row(
      children: [
        Text('Scanning: ${(scanProgress * 100.0).toStringAsFixed(0)} %  ',
            style: BitcoinTextStyle.body5(Bitcoin.neutral7)),
        Expanded(
          child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Bitcoin.blue),
                backgroundColor: Bitcoin.neutral4,
                value: scanProgress,
                minHeight: 6.0,
              )),
        ),
        const SizedBox(
          width: 20,
        ),
        Image(
          width: 20.0,
          image: const AssetImage("icons/2.0x/caret_right.png",
              package: "bitcoin_ui"),
          color: Bitcoin.neutral7,
        )
      ],
    );
  }

  Widget buildDanaAddressBanner(Bip353Address danaAddress) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: danaAddress.toString()));
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Bitcoin.white, size: 16),
                const SizedBox(width: 8),
                const Text('Dana address copied to clipboard'),
              ],
            ),
            backgroundColor: Bitcoin.green.withValues(alpha: 0.8),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Bitcoin.blue.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Bitcoin.blue.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Your Dana Address',
                    style: BitcoinTextStyle.body4(Bitcoin.neutral7).copyWith(
                        fontFamily: 'Inter', fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  danaAddress.asRichText(15.0),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.copy,
                size: 16, color: Bitcoin.blue.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  Widget buildOfflineStatus(ChainState chainState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Bitcoin.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Bitcoin.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: Bitcoin.orange, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sync offline - balance may be outdated',
              style: BitcoinTextStyle.body5(Bitcoin.orange),
            ),
          ),
          GestureDetector(
            onTap: () async {
              // Show immediate feedback that retry is happening
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Bitcoin.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('Retrying connection...'),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );

              final success = await chainState.reconnect();

              if (mounted) {
                // Clear the "retrying" message first
                ScaffoldMessenger.of(context).clearSnackBars();

                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Bitcoin.green, size: 16),
                          const SizedBox(width: 8),
                          const Text('Successfully reconnected!'),
                        ],
                      ),
                      backgroundColor: Bitcoin.green.withValues(alpha: 0.1),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Bitcoin.orange, size: 16),
                          const SizedBox(width: 8),
                          const Text(
                              'Still unable to connect. Please try again later.'),
                        ],
                      ),
                      backgroundColor: Bitcoin.red.withValues(alpha: 0.8),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Bitcoin.orange,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Retry',
                style: BitcoinTextStyle.body5(Bitcoin.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAmountDisplay(
      ApiAmount amount, FiatExchangeRateState exchangeRate) {
    String btcAmount = hideAmount ? hideAmountFormat : amount.displayBtc();

    String fiatAmount =
        hideAmount ? hideAmountFormat : exchangeRate.displayFiat(amount);

    return GestureDetector(
      onTap: () => setState(() {
        hideAmount = !hideAmount;
      }),
      child: Column(
        children: [
          Text(
            btcAmount,
            style: BitcoinTextStyle.body1(Bitcoin.neutral8).apply(
                fontSizeDelta: 3,
                fontFeatures: [const FontFeature.slashedZero()]),
          ),
          Text(
            fiatAmount,
            style: BitcoinTextStyle.body3(Bitcoin.neutral6)
                .apply(fontFeatures: [const FontFeature.slashedZero()]),
          ),
        ],
      ),
    );
  }

  ListTile toListTile(
      ApiRecordedTransaction tx, FiatExchangeRateState exchangeRate) {
    Color? color;
    String amount;
    String amountprefix;
    String amountFiat;
    String title;
    String text;
    Image image;
    Widget recipientWidget;
    String date;

    final contactsState = Provider.of<ContactsState>(context);

    switch (tx) {
      case ApiRecordedTransaction_Incoming(:final field0):
        recipientWidget = Text(
          'Incoming',
          style: BitcoinTextStyle.body4(Bitcoin.black),
        );
        date = field0.confirmedAt?.toString() ?? 'Unconfirmed';
        color = Bitcoin.green;
        amount = hideAmount ? hideAmountFormat : field0.amount.displayBtc();
        amountprefix = '+';
        amountFiat = hideAmount
            ? hideAmountFormat
            : exchangeRate.displayFiat(field0.amount);
        title = 'Incoming transaction';
        text = field0.toString();
        image = Image(
            image: const AssetImage("icons/receive.png", package: "bitcoin_ui"),
            color: Bitcoin.neutral3Dark);
      case ApiRecordedTransaction_Outgoing(:final field0):
        final paymentCode = field0.recipients[0].address;
        recipientWidget =
            contactsState.getDisplayNameWidget(context, paymentCode);
        date = field0.confirmedAt?.toString() ?? 'Unconfirmed';
        if (field0.confirmedAt == null) {
          color = Bitcoin.neutral4;
        } else {
          color = Bitcoin.red;
        }
        amount =
            hideAmount ? hideAmountFormat : field0.totalOutgoing().displayBtc();
        amountprefix = '-';
        amountFiat = hideAmount
            ? hideAmountFormat
            : exchangeRate.displayFiat(field0.totalOutgoing());
        title = 'Outgoing transaction';
        text = field0.toString();
        image = Image(
            image: const AssetImage("icons/send.png", package: "bitcoin_ui"),
            color: Bitcoin.neutral3Dark);

      case ApiRecordedTransaction_UnknownOutgoing(:final field0):
        recipientWidget = Text(
          'Unknown',
          style: BitcoinTextStyle.body4(Bitcoin.black),
        );
        date = field0.confirmedAt.toString();
        color = Bitcoin.red;
        amount = hideAmount ? hideAmountFormat : field0.amount.displayBtc();
        amountprefix = '-';
        amountFiat = hideAmount
            ? hideAmountFormat
            : exchangeRate.displayFiat(field0.amount);
        title = 'Parially recovered outgoing transaction';
        text = field0.toString();
        image = Image(
            image: const AssetImage("icons/send.png", package: "bitcoin_ui"),
            color: Bitcoin.neutral3Dark);
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: image,
      title: Row(
        children: [
          Expanded(child: recipientWidget),
          Text('$amountprefix $amount', style: BitcoinTextStyle.body4(color)),
        ],
      ),
      subtitle: Row(
        children: [
          Text(date, style: BitcoinTextStyle.body5(Bitcoin.neutral7)),
          const Spacer(),
          Text(amountFiat, style: BitcoinTextStyle.body5(Bitcoin.neutral7)),
        ],
      ),
      trailing: InkResponse(
          onTap: () {
            showAlertDialog(title, text);
          },
          child: Image(
            image: const AssetImage("icons/caret_right.png",
                package: "bitcoin_ui"),
            color: Bitcoin.neutral7,
          )),
    );
  }

  Widget buildTransactionHistory(List<ApiRecordedTransaction> transactions,
      FiatExchangeRateState exchangeRate) {
    Widget history;
    if (transactions.isEmpty) {
      history = Center(
          child: Text('No transactions yet.',
              style: BitcoinTextStyle.body3(Bitcoin.neutral6)));
    } else {
      history = ListView.separated(
          separatorBuilder: (BuildContext context, int index) =>
              const Divider(),
          reverse: false,
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            return toListTile(
                transactions[transactions.length - 1 - index], exchangeRate);
          });
    }

    return Column(children: [
      Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Recent transactions',
            style: BitcoinTextStyle.body2(Bitcoin.neutral8)
                .apply(fontWeightDelta: 2),
          )),
      LimitedBox(maxHeight: 240, child: history),
    ]);
  }

  Widget buildBottomButtons(String address) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: BitcoinButtonFilled(
              tintColor: danaBlue,
              body: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  'Pay  ',
                  style: BitcoinTextStyle.body3(Bitcoin.white),
                ),
                Image(
                  image:
                      const AssetImage("icons/send.png", package: "bitcoin_ui"),
                  color: Bitcoin.white,
                )
              ]),
              cornerRadius: 6,
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ChooseRecipientScreen())),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAddressBox(String label, String address, bool isDanaAddress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: BitcoinTextStyle.body4(Bitcoin.neutral7),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: address));
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Bitcoin.white, size: 16),
                    const SizedBox(width: 8),
                    const Text('Address copied to clipboard'),
                  ],
                ),
                backgroundColor: Bitcoin.green.withValues(alpha: 0.8),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Bitcoin.neutral3,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: isDanaAddress
                      ? Bip353Address.fromString(address).asRichText(15.0)
                      : addressAsRichText(address, 14.0),
                ),
                const SizedBox(width: 8),
                Icon(Icons.copy, size: 16, color: Bitcoin.neutral7),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildFundingScreen(String silentPaymentAddress, String? danaAddress,
      ScanProgressNotifier scanProgress, ChainState chainState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        children: [
          // Show sync progress when actively scanning
          Visibility(
              visible: scanProgress.scanning,
              maintainAnimation: true,
              maintainSize: true,
              maintainState: true,
              child: buildScanProgress(scanProgress.progress)),
          // Show offline status when chain sync has connection issues
          Visibility(
              visible: !chainState.available,
              maintainAnimation: true,
              maintainSize: true,
              maintainState: true,
              child: buildOfflineStatus(chainState)),
          const SizedBox(height: 20.0),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon: arrow down in a box, blue
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Bitcoin.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Image(
                          width: 40,
                          height: 40,
                          image: const AssetImage("icons/receive.png",
                              package: "bitcoin_ui"),
                          color: Bitcoin.blue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Title
                    Text(
                      'Fund your wallet',
                      style: BitcoinTextStyle.body1(Bitcoin.neutral8).apply(
                        fontSizeDelta: 2,
                        fontWeightDelta: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // Subtitle
                    Text(
                      'Your balance is 0 at the moment. Share your Dana address and get donations or fund your wallet to donate to others',
                      style: BitcoinTextStyle.body3(Bitcoin.neutral7),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    // Dana address box (if available)
                    if (danaAddress != null) ...[
                      buildAddressBox('Your Dana Address', danaAddress, true),
                      const SizedBox(height: 20),
                    ],
                    // Silent payment address box, only show this if dana address is not present
                    if (danaAddress == null)
                      buildAddressBox('Your Silent Payment Address',
                          silentPaymentAddress, false),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  AppBar buildAppBar(bool isScanning, Color networkColor) {
    return AppBar(
      forceMaterialTransparency: true,
      title: Row(
        children: [
          const Spacer(),
          SizedBox(
              height: 30.0,
              width: 30.0,
              child: Image(
                fit: BoxFit.contain,
                image: const AssetImage("icons/3.0x/bitcoin_circle.png",
                    package: "bitcoin_ui"),
                color: networkColor,
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletState = Provider.of<WalletState>(context);
    final exchangeRate = Provider.of<FiatExchangeRateState>(context);
    final scanProgress = Provider.of<ScanProgressNotifier>(context);
    final chainState = Provider.of<ChainState>(context);
    final danaAddress = walletState.danaAddress;

    ApiAmount amount = walletState.amount + walletState.unconfirmedChange;

    // Check if balance is zero
    bool isBalanceZero = amount.field0 == BigInt.zero;
    // Check if there's transaction history
    bool hasTransactionHistory =
        walletState.txHistory.toApiTransactions().isNotEmpty;

    // Show funding screen only if balance is zero AND there's no transaction history
    bool showFundingScreen = isBalanceZero && !hasTransactionHistory;

    return Scaffold(
        appBar: buildAppBar(scanProgress.scanning, walletState.network.toColor),
        body: showFundingScreen
            ? buildFundingScreen(
                walletState.receivePaymentCode,
                danaAddress?.toString(),
                scanProgress,
                chainState,
              )
            : Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Show sync progress when actively scanning
                          Visibility(
                              visible: scanProgress.scanning,
                              maintainAnimation: true,
                              maintainSize: true,
                              maintainState: true,
                              child: buildScanProgress(scanProgress.progress)),
                          // Show offline status when chain sync has connection issues
                          Visibility(
                              visible: !chainState.available,
                              maintainAnimation: true,
                              maintainSize: true,
                              maintainState: true,
                              child: buildOfflineStatus(chainState)),
                          const SizedBox(height: 20.0),
                          buildAmountDisplay(
                            amount,
                            exchangeRate,
                          ),
                          const SizedBox(height: 20.0),
                          // Show Dana address banner if available
                          if (danaAddress != null)
                            buildDanaAddressBanner(danaAddress),
                          const Spacer(),
                          buildTransactionHistory(
                            walletState.txHistory.toApiTransactions(),
                            exchangeRate,
                          ),
                          buildBottomButtons(walletState.receivePaymentCode),
                          const SizedBox(
                            height: 20.0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ));
  }
}
