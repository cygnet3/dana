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
  final String? initialAddress;

  const ChooseRecipientScreen({super.key, this.initialAddress});

  @override
  ChooseRecipientScreenState createState() => ChooseRecipientScreenState();
}

class ChooseRecipientScreenState extends State<ChooseRecipientScreen> {
  late final TextEditingController textFieldController;
  String? _addressErrorText;

  @override
  void initState() {
    super.initState();
    textFieldController = TextEditingController(
      text: widget.initialAddress ?? '',
    );
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
          contact.displayNameInitial,
          style:
              BitcoinTextStyle.body5(Bitcoin.white).apply(fontWeightDelta: 2),
        ),
      ),
      title: Text(
        contact.displayName,
        style: BitcoinTextStyle.body5(Bitcoin.black),
      ),
      onTap: () {
        setState(() {
          _addressErrorText = null;
          textFieldController.text = contact.paymentCode;
        });
        FocusScope.of(context).unfocus();
        onContinue();
      },
    );
  }

  Future<void> onContinue() async {
    setState(() {
      _addressErrorText = null;
    });

    final network = Provider.of<ChainState>(context, listen: false).network;
    final youContact =
        Provider.of<ContactsState>(context, listen: false).getYouContact();

    try {
      Bip353Address? bip353Address;
      String paymentCode;

      String textField = textFieldController.text.trim();

      if (textField.isEmpty) {
        throw Exception("Please enter a valid payment info");
      } else if (textField == youContact.paymentCode) {
        throw Exception("You cannot send to yourself");
      }

      if (textField.contains('@')) {
        // we interpret the input as a bip353 address
        Logger().d('Resolving dana address: "$textField"');

        bip353Address = Bip353Address.fromString(textField);

        final resolvedPaymentCode =
            await Bip353Resolver.resolve(bip353Address, network);

        if (resolvedPaymentCode == null) {
          // DNS resolution returned null - address not registered
          Logger().w('Dana address "$textField" not found in DNS');
          throw Exception('Dana address not found or not registered');
        }

        // set payment code to resolved code
        paymentCode = resolvedPaymentCode;

        if (paymentCode == youContact.paymentCode) {
          throw Exception("You cannot send to yourself");
        }

        Logger().d(
            'Successfully resolved dana address to SP address: ${resolvedPaymentCode.substring(0, 20)}...');
      } else {
        // we interpret the input field as an on-chain address
        paymentCode = textField;
      }

      try {
        validateAddressWithNetwork(address: paymentCode, network: network);
      } catch (e) {
        if (e.toString().contains('network')) {
          throw InvalidNetworkException();
        } else {
          throw InvalidAddressException();
        }
      }

      // Use existing contact so amount screen shows name; otherwise minimal Contact.
      if (!mounted) return;
      final contactsState = Provider.of<ContactsState>(context, listen: false);
      final existingContact =
          contactsState.getContactByPaymentCode(paymentCode);
      final recipient = existingContact ??
          Contact(bip353Address: bip353Address, paymentCode: paymentCode);

      goToScreen(context, AmountSelectionScreen(recipient: recipient));
      if (!mounted) return;
      setState(() {
        textFieldController.clear();
        _addressErrorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addressErrorText = exceptionToString(e);
      });
    }
  }

  Future<void> onPasteFromClipboard() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null) {
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
      textFieldController.text = result;
      await onContinue();
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsState = Provider.of<ContactsState>(context);
    final query = textFieldController.text.toLowerCase().trim();
    final filteredContacts = contactsState.filterContacts(query);
    final hasQuery = query.isNotEmpty;

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
                      title: "Paste an address from clipboard",
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
