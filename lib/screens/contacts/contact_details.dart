import 'package:barcode_widget/barcode_widget.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/data/models/recipient_form.dart';
import 'package:danawallet/generated/rust/api/structs/recorded_transaction.dart';
import 'package:danawallet/generated/rust/api/validate.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/data/models/contact_field.dart';
import 'package:danawallet/services/bip353_resolver.dart';
import 'package:danawallet/screens/contacts/add_edit_field_sheet.dart';
import 'package:danawallet/screens/contacts/edit_contact_sheet.dart';
import 'package:danawallet/screens/spend/amount_selection.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/back_button.dart';
import 'package:danawallet/widgets/loading_widget.dart';
import 'package:danawallet/widgets/text/scrollable_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:text_scroll/text_scroll.dart';

class ContactDetailsScreen extends StatelessWidget {
  final int contactId;

  const ContactDetailsScreen({super.key, required this.contactId});

  String _formatAddress(String address) {
    if (address.length <= 20) {
      // If address is short, just group by 4
      return _groupByFour(address);
    }

    // First 12 characters grouped by 4
    final firstPart = _groupByFour(address.substring(0, 12));
    // Last 8 characters grouped by 4
    final lastPart = _groupByFour(address.substring(address.length - 8));

    return '$firstPart ... $lastPart';
  }

  String _groupByFour(String text) {
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i += 4) {
      if (i > 0) buffer.write(' ');
      final end = (i + 4 < text.length) ? i + 4 : text.length;
      buffer.write(text.substring(i, end));
    }
    return buffer.toString();
  }

  Future<void> _copyDanaAddress(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    displayNotification("Copied Dana address to clipboard");
  }

  void _showEditContactSheet(BuildContext context, Contact contact) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditContactSheet(
        contact: contact,
      ),
    );
  }

  Widget _buildCustomFieldItem(BuildContext context, ContactField field) {
    return ListTile(
      title: Text(
        field.fieldType,
        style: BitcoinTextStyle.body3(Bitcoin.black).apply(fontWeightDelta: 1),
      ),
      subtitle: Text(
        field.fieldValue,
        style: BitcoinTextStyle.body5(Bitcoin.neutral7),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: Bitcoin.neutral7),
        onSelected: (value) async {
          if (value == 'edit') {
            _showEditFieldSheet(context, field);
          } else if (value == 'delete') {
            _deleteField(context, field);
          } else if (value == 'copy') {
            Clipboard.setData(ClipboardData(text: field.fieldValue));
            HapticFeedback.lightImpact();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'copy',
            child: Row(
              children: [
                Icon(Icons.copy, size: 20),
                SizedBox(width: 8),
                Text('Copy'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit, size: 20),
                SizedBox(width: 8),
                Text('Edit'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, size: 20, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
      onTap: () {
        _showEditFieldSheet(context, field);
      },
    );
  }

  void _showAddFieldSheet(BuildContext context, int contactId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddEditFieldSheet(
        contactId: contactId,
      ),
    );
  }

  void _showEditFieldSheet(BuildContext context, ContactField field) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddEditFieldSheet(
        field: field,
        contactId: contactId,
      ),
    );
  }

  Future<void> _deleteField(BuildContext context, ContactField field) async {
    final contacts = Provider.of<ContactsState>(context, listen: false);

    if (field.id == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Field'),
        content: Text('Are you sure you want to delete "${field.fieldType}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        contacts.deleteContactField(field.id!);
        displayNotification("Field deleted");
      } catch (e) {
        displayError("Failed to delete field", e);
      }
    }
  }

  Future<void> _onSendBitcoin(BuildContext context, Contact contact) async {
    // If a dana address is present, we must verify it
    Bip353Address? bip353 = contact.bip353Address;
    String paymentCode = contact.paymentCode;
    final network = Provider.of<ChainState>(context, listen: false).network;

    try {
      validateAddressWithNetwork(
          address: paymentCode, network: network.toCoreArg);
    } catch (e) {
      displayError("Network validation error", e);
      return;
    }

    if (bip353 != null) {
      // If contact has a bip353-address, the contact was probably added using bip353.
      // We have to verify if the underlying payment code is the same.
      try {
        final verified = await Bip353Resolver.verifyPaymentCode(
            bip353, paymentCode, network);
        if (!verified) {
          displayWarning(
              "Man-in-the-middle attack might be occurring! Sending not possible");
          return;
        }
      } catch (e) {
        displayError("Sending failed", e);
        return;
      }
    }

    final form = RecipientForm();
    form.reset();
    form.recipient = contact;

    if (context.mounted) {
      goToScreen(context, const AmountSelectionScreen());
    }
  }

  Future<void> _copyStaticAddress(
      BuildContext context, String paymentCode) async {
    // first pop to show notification
    Navigator.of(context).pop();
    await Clipboard.setData(ClipboardData(text: paymentCode));
    HapticFeedback.lightImpact();
    displayNotification("Copied static address to clipboard");
  }

  void _showStaticAddressSheet(BuildContext context, String paymentCode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(25.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Bitcoin.neutral4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Text(
              'Static Address',
              style: BitcoinTextStyle.title4(Bitcoin.black),
            ),
            const SizedBox(height: 20),
            // QR Code
            GestureDetector(
              onTap: () => _copyStaticAddress(context, paymentCode),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Bitcoin.neutral2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: BarcodeWidget(
                  data: paymentCode,
                  barcode: Barcode.qrCode(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Address text
            GestureDetector(
              onTap: () => _copyStaticAddress(context, paymentCode),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Bitcoin.neutral2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      'tap to copy',
                      style: BitcoinTextStyle.body5(Bitcoin.neutral5),
                    ),
                    const SizedBox(height: 8),
                    addressAsRichText(paymentCode, 14.0),
                  ],
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
        ),
      ),
    );
  }

  List<ApiRecordedTransaction> _getSentTransactions(
      BuildContext context, Contact contact) {
    final walletState = Provider.of<WalletState>(context, listen: false);
    final allTransactions = walletState.txHistory.toApiTransactions();
    final contactPaymentCode = contact.paymentCode;

    // Filter to only outgoing transactions where recipient matches this contact's SP address
    return allTransactions.where((tx) {
      if (tx is ApiRecordedTransaction_Outgoing) {
        // Check if any recipient matches the contact's SP address
        return tx.field0.recipients
            .any((recipient) => recipient.address == contactPaymentCode);
      }
      return false;
    }).toList();
  }

  ListTile _buildTransactionTile(ApiRecordedTransaction tx,
      FiatExchangeRateState exchangeRate, Contact contact) {
    // Only handle outgoing transactions (we filter for those)
    if (tx is! ApiRecordedTransaction_Outgoing) {
      throw Exception('Expected outgoing transaction');
    }

    final field0 = tx.field0;
    final recipient = contact.displayName;
    final date = field0.confirmedAt?.toString() ?? 'Unconfirmed';
    final color = field0.confirmedAt == null ? Bitcoin.neutral4 : Bitcoin.red;
    final amount = field0.totalOutgoing().displayBtc();
    const amountprefix = '-';
    final amountFiat = exchangeRate.displayFiat(field0.totalOutgoing());
    const title = 'Outgoing transaction';
    final text = field0.toString();
    final image = Image(
        image: const AssetImage("icons/send.png", package: "bitcoin_ui"),
        color: Bitcoin.neutral3Dark);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: image,
      title: Row(
        children: [
          Text(
            recipient,
            style: BitcoinTextStyle.body4(Bitcoin.black),
          ),
          const Spacer(),
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

  void _showSentTransactionsSheet(BuildContext context, Contact contact) {
    final exchangeRate =
        Provider.of<FiatExchangeRateState>(context, listen: false);
    final sentTransactions = _getSentTransactions(context, contact);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(25.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Bitcoin.neutral4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Text(
              'Sent to ${contact.displayName}',
              style: BitcoinTextStyle.title4(Bitcoin.black),
            ),
            const SizedBox(height: 20),
            // Transactions list
            Flexible(
              child: sentTransactions.isEmpty
                  ? Center(
                      child: Text(
                        'No transactions sent to this contact',
                        style: BitcoinTextStyle.body3(Bitcoin.neutral6),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      separatorBuilder: (context, index) => const Divider(),
                      reverse: false,
                      itemCount: sentTransactions.length,
                      itemBuilder: (context, index) {
                        return _buildTransactionTile(
                          sentTransactions[sentTransactions.length - 1 - index],
                          exchangeRate,
                          contact,
                        );
                      },
                    ),
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = Provider.of<ContactsState>(context);
    final contact = contacts.getContact(contactId);
    final customFields = contact?.customFields;

    if (contact == null) {
      return const LoadingWidget();
    }

    // if we're the 'you' contact, we don't show certain things
    final isYouContact = contact == contacts.getYouContact();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const BackButtonWidget(),
        actions: [
          if (!isYouContact)
            IconButton(
              icon: Icon(Icons.edit, color: Bitcoin.black),
              onPressed: () {
                _showEditContactSheet(context, contact);
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // Avatar
            CircleAvatar(
              radius: 50,
              backgroundColor: contact.avatarColor,
              child: Text(
                contact.displayNameInitial,
                style: BitcoinTextStyle.body1(Bitcoin.white)
                    .apply(fontWeightDelta: 2, fontSizeDelta: 3),
              ),
            ),
            const SizedBox(height: 20),
            // Name in bold
            Text(
              contact.name!,
              style: BitcoinTextStyle.body2(Bitcoin.black)
                  .apply(fontWeightDelta: 2),
            ),
            const SizedBox(height: 8),
            // Dana address slightly smaller - tappable to copy
            if (contact.bip353Address != null)
              GestureDetector(
                onTap: () =>
                    _copyDanaAddress(contact.bip353Address!.toString()),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                        child: ScrollableText(
                            text: contact.bip353Address!.toString(),
                            style: BitcoinTextStyle.body4(Bitcoin.neutral7))),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.copy,
                      size: 16,
                      color: Bitcoin.neutral7,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 30),
            // Send Bitcoin button
            if (!isYouContact)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: BitcoinButtonFilled(
                  tintColor: danaBlue,
                  body: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Send Bitcoin  ',
                        style: BitcoinTextStyle.body3(Bitcoin.white),
                      ),
                      Image(
                        image: const AssetImage("icons/send.png",
                            package: "bitcoin_ui"),
                        color: Bitcoin.white,
                      ),
                    ],
                  ),
                  cornerRadius: 6,
                  onPressed: () {
                    _onSendBitcoin(context, contact);
                  },
                ),
              ),
            const SizedBox(height: 30),
            // List of items
            Expanded(
              child: ListView(
                children: [
                  // Static Address item
                  ListTile(
                    title: Text(
                      'Static Address',
                      style: BitcoinTextStyle.body3(Bitcoin.black)
                          .apply(fontWeightDelta: 1),
                    ),
                    subtitle: Text(
                      _formatAddress(contact.paymentCode),
                      style: BitcoinTextStyle.body5(Bitcoin.neutral7),
                    ),
                    trailing:
                        Icon(Icons.chevron_right, color: Bitcoin.neutral7),
                    onTap: () {
                      _showStaticAddressSheet(context, contact.paymentCode);
                    },
                  ),
                  if (!isYouContact) ...[
                    const Divider(),
                    // Sent item
                    ListTile(
                      title: Text(
                        'Sent',
                        style: BitcoinTextStyle.body3(Bitcoin.black)
                            .apply(fontWeightDelta: 1),
                      ),
                      trailing:
                          Icon(Icons.chevron_right, color: Bitcoin.neutral7),
                      onTap: () {
                        _showSentTransactionsSheet(context, contact);
                      },
                    ),
                    const Divider(),
                    // Custom Fields Section
                    if (customFields != null && customFields.isNotEmpty) ...[
                      ...customFields.map(
                          (field) => _buildCustomFieldItem(context, field)),
                    ],
                    ListTile(
                      leading: Icon(Icons.add, color: Bitcoin.blue),
                      title: Text(
                        'Add Field',
                        style: BitcoinTextStyle.body3(Bitcoin.blue)
                            .apply(fontWeightDelta: 1),
                      ),
                      onTap: () {
                        _showAddFieldSheet(context, contactId);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
