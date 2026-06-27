import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/exceptions.dart';
import 'package:danawallet/generated/rust/api/validate.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/spend/amount_selection.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/services/bip353_resolver.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button_outlined.dart';
import 'package:danawallet/widgets/qr_code_scanner_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class ChooseRecipientScreen extends StatefulWidget {
  const ChooseRecipientScreen({super.key});

  @override
  ChooseRecipientScreenState createState() => ChooseRecipientScreenState();
}

class ChooseRecipientScreenState extends State<ChooseRecipientScreen> {
  late final TextEditingController textFieldController;
  String? _addressErrorText;
  bool _showContactSuggestions = true;

  @override
  void initState() {
    super.initState();
    textFieldController = TextEditingController();
  }

  @override
  void dispose() {
    textFieldController.dispose();
    super.dispose();
  }

  Widget _buildContactSuggestionItem(Contact contact) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: contact.avatarColor,
        child: Text(
          contact.displayNameInitial ?? '?',
          style:
              BitcoinTextStyle.body5(Bitcoin.white).apply(fontWeightDelta: 2),
        ),
      ),
      title: Text(
        contact.displayName ?? '?',
        style: BitcoinTextStyle.body5(Bitcoin.black),
      ),
      onTap: () {
        setState(() => _addressErrorText = null);
        FocusScope.of(context).unfocus();
        onContinue(contact: contact);
      },
    );
  }

  Future<void> onContinue({Contact? contact}) async {
    setState(() {
      _addressErrorText = null;
    });

    final network = Provider.of<ChainState>(context, listen: false).network;
    final youContact =
        Provider.of<ContactsState>(context, listen: false).getYouContact();

    try {
      final String resolvedPaymentCode;
      final Bip353Address? resolvedBip353;

      if (contact != null) {
        // Selected from contact list — use contact data directly, leave field unchanged.
        resolvedPaymentCode = contact.paymentCode;
        resolvedBip353 = contact.bip353Address;
      } else {
        final textField = textFieldController.text.trim();

        if (textField.isEmpty) {
          throw Exception("Please enter a valid payment info");
        } else if (textField == youContact.paymentCode) {
          throw Exception("You cannot send to yourself");
        }

        if (textField.contains('@')) {
          Logger().d('Resolving dana address: "$textField"');

          final parsed = Bip353Address.fromString(textField);
          final resolved = await Bip353Resolver.resolve(parsed, network);

          if (resolved == null) {
            Logger().w('Dana address "$textField" not found in DNS');
            throw Exception('Dana address not found or not registered');
          }

          resolvedPaymentCode = resolved;
          resolvedBip353 = parsed;

          if (resolvedPaymentCode == youContact.paymentCode) {
            throw Exception("You cannot send to yourself");
          }

          Logger().d(
              'Successfully resolved dana address to SP address: ${resolvedPaymentCode.substring(0, 20)}...');
        } else {
          resolvedPaymentCode = textField;
          resolvedBip353 = null;
        }
      }

      if (resolvedPaymentCode == youContact.paymentCode) {
        throw Exception("You cannot send to yourself");
      }

      try {
        validateAddressWithNetwork(
            address: resolvedPaymentCode, network: network);
      } catch (e) {
        if (e.toString().contains('network')) {
          throw InvalidNetworkException();
        } else {
          throw InvalidAddressException();
        }
      }

      if (mounted) {
        goToScreen(
            context,
            AmountSelectionScreen(
              paymentCode: resolvedPaymentCode,
              providedBip353: resolvedBip353,
            ));
      }
    } catch (e) {
      setState(() {
        _addressErrorText = exceptionToString(e);
      });
    }
  }

  Future<void> onPasteFromClipboard() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null) {
      setState(() => _showContactSuggestions = false);
      textFieldController.text = data.text ?? '';
      await onContinue();
    }
  }

  Future<void> onScanWithCamera() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QRCodeScannerWidget(),
      ),
    );
    if (result is String && result != "") {
      setState(() => _showContactSuggestions = false);
      textFieldController.text = result;
      await onContinue();
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsState = Provider.of<ContactsState>(context);
    final searchText = textFieldController.text.trim();
    final query = searchText.toLowerCase();
    final filteredContacts = contactsState.filterContacts(query);
    final hasQuery = query.isNotEmpty;
    final noContactMatches =
        _showContactSuggestions && hasQuery && filteredContacts.isEmpty;

    return ScreenSkeleton(
        showBackButton: true,
        title: 'Choose recipient(s)',
        body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pay to'),
                  const SizedBox(
                    height: 20.0,
                  ),
                  TextField(
                    onTap: () => setState(() {
                      _addressErrorText = null;
                    }),
                    onChanged: (_) => setState(() {
                      _addressErrorText = null;
                      _showContactSuggestions = true;
                    }),
                    style: BitcoinTextStyle.body4(Bitcoin.black),
                    controller: textFieldController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Look for a contact',
                      hintText:
                          'Type the first letters of one of your contacts',
                      errorText: _addressErrorText,
                    ),
                  ),
                  if (noContactMatches)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        "You don't have any contact that matches \"$searchText\". Do you want to create a new contact?",
                        style: BitcoinTextStyle.body5(Bitcoin.neutral7),
                      ),
                    ),
                  if (hasQuery && filteredContacts.isNotEmpty) ...[
                    const SizedBox(height: 8.0),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filteredContacts.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) =>
                            _buildContactSuggestionItem(
                                filteredContacts[index]),
                      ),
                    ),
                  ],
                ],
              ),
              const Center(child: Text('or')),
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  FooterButtonOutlined(
                      title: "Paste from clipboard",
                      onPressed: onPasteFromClipboard),
                  const SizedBox(
                    height: 10.0,
                  ),
                  FooterButtonOutlined(
                      title: "Scan QR Code", onPressed: onScanWithCamera)
                ],
              ),
              // these work as spacers, will remove them later
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
            ]),
        footer: FooterButton(
          title: 'Continue',
          onPressed: onContinue,
        ));
  }
}
