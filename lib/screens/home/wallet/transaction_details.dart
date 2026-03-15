import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/enums/network.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/generated/rust/api/structs.dart';
import 'package:danawallet/generated/rust/api/validate.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/repositories/transaction_notes_repository.dart';
import 'package:danawallet/screens/contacts/add_contact_sheet.dart';
import 'package:danawallet/screens/contacts/contact_details.dart';
import 'package:danawallet/screens/home/wallet/transaction_note_screen.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class TransactionDetailsScreen extends StatefulWidget {
  final ApiRecordedTransaction transaction;

  const TransactionDetailsScreen({
    super.key,
    required this.transaction,
  });

  @override
  State<TransactionDetailsScreen> createState() =>
      _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState extends State<TransactionDetailsScreen> {
  bool _detailsExpanded = false;
  String? _formattedDate;
  bool _isLoadingDate = false;
  String? _note;
  final _notesRepository = TransactionNotesRepository.instance;

  @override
  void initState() {
    super.initState();
    _fetchTransactionDate();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final txid = _getTxid(widget.transaction);
    final note = await _notesRepository.getNote(txid);
    if (mounted) {
      setState(() => _note = note);
    }
  }

  String _getTxid(ApiRecordedTransaction tx) {
    switch (tx) {
      case ApiRecordedTransaction_Incoming(:final field0):
        return field0.txid;
      case ApiRecordedTransaction_Outgoing(:final field0):
        return field0.txid;
      case ApiRecordedTransaction_UnknownOutgoing(:final field0):
        return field0.spentOutpoints.isNotEmpty ? field0.spentOutpoints[0] : 'unknown';
    }
  }

  Future<void> _openNoteScreen() async {
    final txid = _getTxid(widget.transaction);
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionNoteScreen(
          txid: txid,
          initialNote: _note,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _note = result.isEmpty ? null : result);
    }
  }

  Future<void> _fetchTransactionDate() async {
    final confirmationHeight = _getConfirmationHeight(widget.transaction);
    if (confirmationHeight == null) return;

    setState(() => _isLoadingDate = true);

    try {
      final walletState = Provider.of<WalletState>(context, listen: false);
      final mempoolApi = MempoolApiRepository(network: walletState.network);
      
      final blockHash = await mempoolApi.getBlockHashForHeight(confirmationHeight);
      final block = await mempoolApi.getBlockForHash(blockHash);
      final date = timestampToDate(block.timestamp);
      
      if (mounted) {
        setState(() {
          _formattedDate = DateFormat('MMM d, yyyy \'at\' h:mm a').format(date.toLocal());
          _isLoadingDate = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _formattedDate = null;
          _isLoadingDate = false;
        });
      }
    }
  }

  int? _getConfirmationHeight(ApiRecordedTransaction tx) {
    switch (tx) {
      case ApiRecordedTransaction_Incoming(:final field0):
        return field0.confirmationHeight;
      case ApiRecordedTransaction_Outgoing(:final field0):
        return field0.confirmationHeight;
      case ApiRecordedTransaction_UnknownOutgoing(:final field0):
        return field0.confirmationHeight;
    }
  }

  void _openAddContactSheet(String paymentCode) {
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

  @override
  Widget build(BuildContext context) {
    final walletState = Provider.of<WalletState>(context);
    final chainState = Provider.of<ChainState>(context);
    final exchangeRate = Provider.of<FiatExchangeRateState>(context);
    final contactsState = Provider.of<ContactsState>(context);
    final network = walletState.network;

    // Extract transaction data based on type
    final txData = _extractTransactionData(widget.transaction, exchangeRate);

    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Icon(Icons.chevron_left, color: Bitcoin.neutral8),
              Text('Back', style: BitcoinTextStyle.body4(Bitcoin.neutral8)),
            ],
          ),
        ),
        leadingWidth: 100,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Icon
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
            // Amount
            Text(
              '${txData.amountPrefix}${txData.amount}',
              style: BitcoinTextStyle.title3(txData.amountColor),
            ),
            // Contact label for outgoing transactions (only show if not already a contact)
            if (!txData.isIncoming &&
                txData.recipientAddress != null &&
                isReusablePaymentCode(address: txData.recipientAddress!) &&
                contactsState.getContactByPaymentCode(txData.recipientAddress!) == null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _openAddContactSheet(txData.recipientAddress!),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_add_outlined, size: 16, color: Bitcoin.neutral5),
                    const SizedBox(width: 4),
                    Text('Contact', style: BitcoinTextStyle.body4(Bitcoin.neutral5)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Status row
            _buildStatusRow(txData),
            const SizedBox(height: 24),
            // Info rows
            const Divider(height: 1),
            _buildNoteRow(),
            const Divider(height: 1),
            // For outgoing transactions, show appropriate recipient info
            if (!txData.isIncoming && txData.recipientAddress != null) ...[
              Builder(builder: (context) {
                final isPaymentCode = isReusablePaymentCode(address: txData.recipientAddress!);
                
                if (isPaymentCode) {
                  // For payment codes: show contact tile if contact exists, otherwise recipient row
                  final contact = contactsState.getContactByPaymentCode(txData.recipientAddress!);
                  if (contact != null) {
                    return Column(
                      children: [
                        _buildContactTile(contact),
                        const Divider(height: 1),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _buildRecipientRow(txData.recipientAddress!, contactsState),
                      const Divider(height: 1),
                    ],
                  );
                } else {
                  // For legacy addresses: show onchain address row
                  return Column(
                    children: [
                      _buildOnchainAddressRow(txData.recipientAddress!),
                      const Divider(height: 1),
                    ],
                  );
                }
              }),
            ],
            _buildInfoRow(
              'Date/time',
              txData.date,
            ),
            const Divider(height: 1),
            _buildTransactionIdRow(txData.txid, network),
            const Divider(height: 1),
            // Details expandable section
            _buildDetailsSection(txData, exchangeRate, chainState),
          ],
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

  Widget _buildNoteRow() {
    return GestureDetector(
      onTap: _openNoteScreen,
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
                      _note ?? 'Add note',
                      style: BitcoinTextStyle.body4(
                        _note != null ? Bitcoin.neutral7 : Bitcoin.neutral5,
                      ),
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildContactTile(Contact contact) {
    return GestureDetector(
      onTap: () {
        if (contact.id != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ContactDetailsScreen(contactId: contact.id!),
            ),
          );
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
                style: BitcoinTextStyle.body4(Bitcoin.white).apply(fontWeightDelta: 2),
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

  Widget _buildTransactionIdRow(String txid, Network network) {
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
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _openInBlockExplorer(txid, network),
                child: Icon(Icons.open_in_new,
                    size: 18, color: Bitcoin.neutral7),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientRow(String address, ContactsState contactsState) {
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

  Widget _buildOnchainAddressRow(String address) {
    final truncatedAddress = address.length > 16
        ? '${address.substring(0, 8)}...${address.substring(address.length - 8)}'
        : address;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Onchain address', style: BitcoinTextStyle.body4(Bitcoin.neutral8)),
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
                Text(truncatedAddress, style: BitcoinTextStyle.body4(Bitcoin.neutral7)),
                const SizedBox(width: 4),
                Icon(Icons.copy, size: 14, color: Bitcoin.neutral5),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(
      _TransactionData txData, FiatExchangeRateState exchangeRate, ChainState chainState) {
    // Calculate confirmations: current tip - tx height + 1
    int? confirmations;
    if (txData.confirmationHeight != null && chainState.available) {
      confirmations = chainState.tip - txData.confirmationHeight! + 1;
      if (confirmations < 1) confirmations = 1;
    }

    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Details', style: BitcoinTextStyle.body4(Bitcoin.neutral8)),
                Icon(
                  _detailsExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Bitcoin.neutral7,
                ),
              ],
            ),
          ),
        ),
        if (_detailsExpanded) ...[
          const Divider(height: 1),
          _buildInfoRow('Confirmations', confirmations?.toString() ?? '-'),
          if (txData.confirmationHeight != null)
            _buildInfoRow('Mined in block', txData.confirmationHeight.toString()),
          if (txData.fee != null)
            _buildInfoRow('Fee', txData.fee!.displayBtc()),
          if (txData.change != null && txData.change!.field0 > BigInt.zero)
            _buildInfoRow('Change', txData.change!.displayBtc()),
        ],
      ],
    );
  }

  Future<void> _openInBlockExplorer(String txid, Network network) async {
    if (network == Network.regtest) return;

    try {
      String baseUrl;
      switch (network) {
        case Network.mainnet:
          baseUrl = 'https://mempool.space';
          break;
        case Network.testnet:
          baseUrl = 'https://mempool.space/testnet';
          break;
        case Network.signet:
          baseUrl = 'https://mempool.space/signet';
          break;
        case Network.regtest:
          return;
      }
      final url = Uri.parse('$baseUrl/tx/$txid');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to open block explorer'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open block explorer: $e'),
          ),
        );
      }
    }
  }

  _TransactionData _extractTransactionData(
      ApiRecordedTransaction tx, FiatExchangeRateState exchangeRate) {
    final dateDisplay = _getDateDisplay(tx);
    
    switch (tx) {
      case ApiRecordedTransaction_Incoming(:final field0):
        return _TransactionData(
          txid: field0.txid,
          amount: field0.amount.displaySats(),
          amountPrefix: '+',
          amountColor: Bitcoin.green,
          isIncoming: true,
          confirmationHeight: field0.confirmationHeight,
          date: dateDisplay,
          recipientAddress: null,
          fee: null,
          change: null,
        );
      case ApiRecordedTransaction_Outgoing(:final field0):
        return _TransactionData(
          txid: field0.txid,
          amount: field0.totalOutgoing().displaySats(),
          amountPrefix: '-',
          amountColor: field0.confirmationHeight == null ? Bitcoin.neutral4 : Bitcoin.red,
          isIncoming: false,
          confirmationHeight: field0.confirmationHeight,
          date: dateDisplay,
          recipientAddress:
              field0.recipients.isNotEmpty ? field0.recipients[0].address : null,
          fee: field0.fee,
          change: field0.change,
        );
      case ApiRecordedTransaction_UnknownOutgoing(:final field0):
        return _TransactionData(
          txid: field0.spentOutpoints.isNotEmpty ? field0.spentOutpoints[0] : 'Unknown',
          amount: field0.amount.displaySats(),
          amountPrefix: '-',
          amountColor: Bitcoin.red,
          isIncoming: false,
          confirmationHeight: field0.confirmationHeight,
          date: dateDisplay,
          recipientAddress: null,
          fee: null,
          change: null,
        );
    }
  }

  String _getDateDisplay(ApiRecordedTransaction tx) {
    final confirmationHeight = _getConfirmationHeight(tx);
    
    if (confirmationHeight == null) {
      return 'Pending';
    }
    
    if (_isLoadingDate) {
      return 'Loading...';
    }
    
    if (_formattedDate != null) {
      return _formattedDate!;
    }
    
    // Fallback to block height if date fetch failed
    return 'Block $confirmationHeight';
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
