import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/data/models/recorded_transaction.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/generated/rust/api/validate.dart';
import 'package:danawallet/screens/contacts/add_contact_sheet.dart';
import 'package:danawallet/screens/contacts/contact_details.dart';
import 'package:danawallet/screens/home/wallet/transaction_note_screen.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class TransactionDetailsScreen extends StatelessWidget {
  final int transactionId;

  const TransactionDetailsScreen({
    super.key,
    required this.transactionId,
  });

  void _openNoteScreen(BuildContext context, RecordedTransaction tx) {
    goToScreen(
        context,
        TransactionNoteScreen(
          transactionId: transactionId,
          initialNote: tx.note,
        ));
  }

  void _openAddContactSheet(BuildContext context, String paymentCode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: AddContactSheet(
          initialPaymentCode: paymentCode,
        ),
      ),
    );
  }

  Widget _buildStatusRow(_TransactionData txData) {
    final isPending = txData.confirmationHeight == null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isPending ? 'Payment pending' : 'Confirmed',
          style: BitcoinTextStyle.body4(
            isPending ? Bitcoin.orange : Bitcoin.green,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: BitcoinTextStyle.body4(Bitcoin.neutral8)),
          Text(value, style: BitcoinTextStyle.body4(Bitcoin.neutral7)),
        ],
      ),
    );
  }

  Widget _buildNoteRow(BuildContext context, RecordedTransaction tx) {
    final note = tx.note;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openNoteScreen(context, tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Note', style: BitcoinTextStyle.body4(Bitcoin.neutral8)),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      note?.trimLeft() ?? 'Add note',
                      style: BitcoinTextStyle.body4(
                        note != null ? Bitcoin.neutral7 : Bitcoin.neutral5,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, size: 18, color: Bitcoin.neutral5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactTile(BuildContext context, Contact contact) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (contact.id != null) {
          goToScreen(context, ContactDetailsScreen(contactId: contact.id!));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: contact.avatarColor,
              child: Text(
                contact.displayNameInitial,
                style: BitcoinTextStyle.body4(Bitcoin.white)
                    .apply(fontWeightDelta: 2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                contact.displayName,
                style: BitcoinTextStyle.body4(Bitcoin.neutral8),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: Bitcoin.neutral5),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionIdRow(
      BuildContext context, String txid, ApiNetwork network) {
    final truncatedTxid =
        txid.length > 16 ? '${txid.substring(0, 16)}...' : txid;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Transaction ID',
              style: BitcoinTextStyle.body4(Bitcoin.neutral8)),
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: txid));
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Bitcoin.white, size: 16),
                          const SizedBox(width: 8),
                          const Text('Transaction ID copied'),
                        ],
                      ),
                      backgroundColor: Bitcoin.green.withValues(alpha: 0.8),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(truncatedTxid,
                    style: BitcoinTextStyle.body4(Bitcoin.neutral7)),
              ),
              if (network.defaultBlockExplorerUrl != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _openInBlockExplorer(context, txid, network),
                  child: Icon(Icons.open_in_new,
                      size: 18, color: Bitcoin.neutral7),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientRow(
      BuildContext context, String address, ContactsState contactsState) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Recipient', style: BitcoinTextStyle.body4(Bitcoin.neutral8)),
          Flexible(
            child: contactsState.getDisplayNameWidget(context, address),
          ),
        ],
      ),
    );
  }

  Widget _buildOnchainAddressRow(BuildContext context, String address) {
    final truncatedAddress = address.length > 16
        ? '${address.substring(0, 8)}...${address.substring(address.length - 8)}'
        : address;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Onchain address',
              style: BitcoinTextStyle.body4(Bitcoin.neutral8)),
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
                      const Text('Address copied'),
                    ],
                  ),
                  backgroundColor: Bitcoin.green.withValues(alpha: 0.8),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Row(
              children: [
                Text(truncatedAddress,
                    style: BitcoinTextStyle.body4(Bitcoin.neutral7)),
                const SizedBox(width: 4),
                Icon(Icons.copy, size: 14, color: Bitcoin.neutral5),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(_TransactionData txData, ChainState chainState) {
    int? confirmations;
    if (txData.confirmationHeight != null && chainState.available) {
      confirmations = chainState.tip - txData.confirmationHeight! + 1;
      if (confirmations < 1) confirmations = 1;
    }

    return Column(
      children: [
        if (txData.confirmationHeight != null)
          _buildInfoRow(
              'Mined in block',
              confirmations != null
                  ? '${txData.confirmationHeight} ($confirmations ${confirmations == 1 ? 'confirmation' : 'confirmations'})'
                  : txData.confirmationHeight.toString()),
        if (txData.fee != null) _buildInfoRow('Fee', txData.fee!.displayBtc()),
        if (txData.change != null && txData.change!.field0 > BigInt.zero)
          _buildInfoRow('Change', txData.change!.displayBtc()),
      ],
    );
  }

  Future<void> _openInBlockExplorer(
      BuildContext context, String txid, ApiNetwork network) async {
    final defaultUrl = network.defaultBlockExplorerUrl;
    if (defaultUrl == null) return;

    try {
      final savedUrl = await SettingsRepository.instance.getBlockExplorerUrl();
      final url = Uri.parse('${savedUrl ?? defaultUrl}/tx/$txid');
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
  }

  _TransactionData _extractTransactionData(
      RecordedTransaction tx, FiatExchangeRateState exchangeRate) {
    final dateDisplay = _getDateDisplay(tx);

    switch (tx) {
      case RecordedTransactionIncoming incoming:
        return _TransactionData(
          txid: incoming.txid,
          amount: incoming.amount.displaySats(),
          amountPrefix: '+',
          amountColor: Bitcoin.green,
          isIncoming: true,
          confirmationHeight: incoming.confirmationHeight,
          date: dateDisplay,
          recipientAddress: null,
          fee: null,
          change: null,
        );
      case RecordedTransactionOutgoing outgoing:
        return _TransactionData(
          txid: outgoing.txid,
          amount: outgoing.totalOutgoing().displaySats(),
          amountPrefix: '-',
          amountColor: outgoing.confirmationHeight == null
              ? Bitcoin.neutral4
              : Bitcoin.red,
          isIncoming: false,
          confirmationHeight: outgoing.confirmationHeight,
          date: dateDisplay,
          recipientAddress: outgoing.recipients.isNotEmpty
              ? outgoing.recipients[0].paymentCode
              : null,
          fee: outgoing.fee,
          change: outgoing.change,
        );
      case RecordedTransactionUnknownOutgoing unknown:
        return _TransactionData(
          txid: 'Unknown',
          amount: unknown.amount.displaySats(),
          amountPrefix: '-',
          amountColor: Bitcoin.red,
          isIncoming: false,
          confirmationHeight: unknown.confirmationHeight,
          date: dateDisplay,
          recipientAddress: null,
          fee: null,
          change: null,
        );
    }
  }

  String _getDateDisplay(RecordedTransaction tx) {
    if (tx.confirmationHeight == null) {
      return 'Pending';
    }

    final timestamp = tx.confirmationTimestamp;
    if (timestamp != null) {
      return timestamp.toDate().toLocal().toDisplayString();
    }

    return 'Block ${tx.confirmationHeight}';
  }

  @override
  Widget build(BuildContext context) {
    final walletState = Provider.of<WalletState>(context);
    final chainState = Provider.of<ChainState>(context);
    final exchangeRate = Provider.of<FiatExchangeRateState>(context);
    final contactsState = Provider.of<ContactsState>(context);
    final network = walletState.network;

    final transaction = walletState.transactions.firstWhere(
      (t) => t.id == transactionId,
    );
    final txData = _extractTransactionData(transaction, exchangeRate);

    return ScreenSkeleton(
      showBackButton: true,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: txData.isIncoming
                    ? Bitcoin.orange.withValues(alpha: 0.2)
                    : Bitcoin.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Image(
                  width: 36,
                  height: 36,
                  image: AssetImage(
                    txData.isIncoming ? "icons/receive.png" : "icons/send.png",
                    package: "bitcoin_ui",
                  ),
                  color:
                      txData.isIncoming ? Bitcoin.orange : Bitcoin.neutral3Dark,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${txData.amountPrefix}${txData.amount}',
              style: BitcoinTextStyle.title3(txData.amountColor),
            ),
            if (!txData.isIncoming &&
                txData.recipientAddress != null &&
                isReusablePaymentCode(address: txData.recipientAddress!) &&
                contactsState
                        .getContactByPaymentCode(txData.recipientAddress!) ==
                    null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () =>
                    _openAddContactSheet(context, txData.recipientAddress!),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_add_outlined,
                        size: 16, color: Bitcoin.neutral5),
                    const SizedBox(width: 4),
                    Text('Contact',
                        style: BitcoinTextStyle.body4(Bitcoin.neutral5)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildStatusRow(txData),
            const SizedBox(height: 24),
            const Divider(height: 1),
            _buildNoteRow(context, transaction),
            const Divider(height: 1),
            if (!txData.isIncoming && txData.recipientAddress != null) ...[
              Builder(builder: (context) {
                final isPaymentCode =
                    isReusablePaymentCode(address: txData.recipientAddress!);

                if (isPaymentCode) {
                  final contact = contactsState
                      .getContactByPaymentCode(txData.recipientAddress!);
                  if (contact != null) {
                    return Column(
                      children: [
                        _buildContactTile(context, contact),
                        const Divider(height: 1),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _buildRecipientRow(
                          context, txData.recipientAddress!, contactsState),
                      const Divider(height: 1),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildOnchainAddressRow(
                          context, txData.recipientAddress!),
                      const Divider(height: 1),
                    ],
                  );
                }
              }),
            ],
            _buildInfoRow('Date/time', txData.date),
            const Divider(height: 1),
            _buildTransactionIdRow(context, txData.txid, network),
            const Divider(height: 1),
            _buildDetailsSection(txData, chainState),
          ],
        ),
      ),
    );
  }
}

class _TransactionData {
  final String txid;
  final String amount;
  final String amountPrefix;
  final Color amountColor;
  final bool isIncoming;
  final int? confirmationHeight;
  final String date;
  final String? recipientAddress;
  final ApiAmount? fee;
  final ApiAmount? change;

  _TransactionData({
    required this.txid,
    required this.amount,
    required this.amountPrefix,
    required this.amountColor,
    required this.isIncoming,
    required this.confirmationHeight,
    required this.date,
    required this.recipientAddress,
    required this.fee,
    required this.change,
  });
}
