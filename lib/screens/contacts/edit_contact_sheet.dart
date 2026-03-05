import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/services/bip353_resolver.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class EditContactSheet extends StatefulWidget {
  final Contact contact;

  const EditContactSheet({
    super.key,
    required this.contact,
  });

  @override
  State<EditContactSheet> createState() => _EditContactSheetState();
}

class _EditContactSheetState extends State<EditContactSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bip353Controller = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _bip353FocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();
  bool _isUpdating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // name must be present for existing contacts
    _nameController.text = widget.contact.name!;
    _bip353Controller.text = widget.contact.bip353Address?.toString() ?? '';
    _nameFocusNode.addListener(_clearError);
    _bip353FocusNode.addListener(_clearError);
  }

  @override
  void dispose() {
    _bip353FocusNode.dispose();
    _nameFocusNode.dispose();
    _bip353Controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  Future<void> _updateContact() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final contacts = Provider.of<ContactsState>(context, listen: false);
    final network = Provider.of<ChainState>(context, listen: false).network;

    final newName = _nameController.text.trim();
    final newBip353 = _bip353Controller.text.trim();

    setState(() {
      _isUpdating = true;
    });

    if (newName.isEmpty) {
      setState(() {
        _errorMessage = 'Name is required';
        _isUpdating = false;
      });
      return;
    }

    final Bip353Address? newBip353Parsed;
    if (newBip353.isNotEmpty) {
      try {
        newBip353Parsed = Bip353Address.fromString(newBip353);
      } catch (e) {
        setState(() {
          _isUpdating = false;
          _errorMessage = e.toString();
        });
        return;
      }
    } else {
      newBip353Parsed = null;
    }

    try {
      // If we have dana address but no SP address, try to resolve it
      if (newBip353Parsed != null) {
        try {
          final resolved =
              await Bip353Resolver.resolve(newBip353Parsed, network);
          if (resolved == null) {
            setState(() {
              _isUpdating = false;
              _errorMessage = 'Address not found';
            });
            return;
          }
          // updated bip353 address *must* point to same underlying payment code
          else if (resolved != widget.contact.paymentCode) {
            setState(() {
              _isUpdating = false;
              _errorMessage =
                  'Updated address points to different payment code, please make a new contact instead';
            });
            return;
          }
        } catch (e) {
          setState(() {
            _isUpdating = false;
            _errorMessage = 'Failed to resolve payment code: $e';
          });
          return;
        }
      }

      // Update the contact
      final updatedContact = Contact(
        id: widget.contact.id,
        name: newName,
        bip353Address: newBip353Parsed,
        // these entries don't change
        paymentCode: widget.contact.paymentCode,
        customFields: widget.contact.customFields,
      );

      await contacts.updateContact(updatedContact);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      Logger().e('Failed to update contact: $e');
      if (mounted) {
        setState(() {
          _isUpdating = false;
          _errorMessage = 'Failed to update contact: $e';
        });
      }
    }
  }

  Future<void> _deleteContact() async {
    if (widget.contact.id == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text(
            'Are you sure you want to delete "${widget.contact.displayName}"? This action cannot be undone.'),
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

    if (confirmed == true && mounted) {
      try {
        final contacts = Provider.of<ContactsState>(context, listen: false);
        await contacts.deleteContact(widget.contact.id!);
      } catch (e) {
        displayError("Failed to delete contact", e);
      }

      if (mounted) goToHomeScreen(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(25.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              'Edit Contact',
              style: BitcoinTextStyle.title4(Bitcoin.black),
            ),
            const SizedBox(height: 20),
            // Name field
            TextField(
              controller: _nameController,
              focusNode: _nameFocusNode,
              style: BitcoinTextStyle.body4(Bitcoin.black),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Name',
                hintText: 'Contact name',
              ),
            ),
            const SizedBox(height: 16),
            // Dana address field
            TextField(
              controller: _bip353Controller,
              focusNode: _bip353FocusNode,
              style: BitcoinTextStyle.body4(Bitcoin.black),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Dana Address',
                hintText: 'user@domain.com',
              ),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: BitcoinTextStyle.body5(Bitcoin.red),
              ),
            ],
            const SizedBox(height: 20),
            // Save button
            FooterButton(
              title: _isUpdating ? 'Updating...' : 'Update',
              onPressed: _isUpdating ? null : _updateContact,
              enabled: !_isUpdating,
            ),
            const SizedBox(height: 12),
            // Delete button
            FooterButton(
              title: 'Delete Contact',
              onPressed: _deleteContact,
              color: Colors.red,
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
        ),
      ),
    );
  }
}
