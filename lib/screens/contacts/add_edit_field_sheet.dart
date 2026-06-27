import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/contact_field.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/sheets/app_bottom_sheet_shell.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddEditFieldSheet extends StatefulWidget {
  final ContactField?
      field; // If null, we're adding; if not null, we're editing
  final int contactId;

  const AddEditFieldSheet({
    super.key,
    this.field,
    required this.contactId,
  });

  @override
  State<AddEditFieldSheet> createState() => _AddEditFieldSheetState();
}

class _AddEditFieldSheetState extends State<AddEditFieldSheet> {
  final TextEditingController _fieldTypeController = TextEditingController();
  final TextEditingController _fieldValueController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  String? _errorMessage;
  bool _isCustomType = false;
  String? _selectedFieldType;

  // Common field types
  static const List<String> commonFieldTypes = [
    'Email',
    'X',
    'Telegram',
    'GitHub',
    'Phone',
    'Website',
    'Nostr',
    'Notes',
    'Custom',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.field != null) {
      _fieldValueController.text = widget.field!.fieldValue;
      _isCustomType = !commonFieldTypes.contains(widget.field!.fieldType);
      if (_isCustomType) {
        _fieldTypeController.text = widget.field!.fieldType;
      } else {
        _selectedFieldType = widget.field!.fieldType;
        _fieldTypeController.text = widget.field!.fieldType;
      }
    }
  }

  @override
  void dispose() {
    _fieldTypeController.dispose();
    _fieldValueController.dispose();
    super.dispose();
  }

  Future<void> _saveField() async {
    String fieldType;

    if (_isCustomType) {
      fieldType = _fieldTypeController.text.trim();
    } else {
      fieldType = _selectedFieldType ?? '';
    }

    final fieldValue = _fieldValueController.text.trim();

    if (fieldType.isEmpty) {
      setState(() {
        _errorMessage = 'Field type is required';
      });
      return;
    }

    if (fieldValue.isEmpty) {
      setState(() {
        _errorMessage = 'Field value is required';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      if (widget.field != null) {
        // Update existing field
        final updatedField = ContactField(
          id: widget.field!.id,
          contactId: widget.contactId,
          fieldType: fieldType,
          fieldValue: fieldValue,
        );
        await Provider.of<ContactsState>(context, listen: false)
            .updateContactField(updatedField);
      } else {
        // Create new field
        await Provider.of<ContactsState>(context, listen: false)
            .addContactField(
          contactId: widget.contactId,
          fieldType: fieldType,
          fieldValue: fieldValue,
        );
      }

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save field: $e';
        });
      }
    }
  }

  void _onFieldTypeChanged(String? value) {
    if (value == 'Custom') {
      setState(() {
        _isCustomType = true;
        _selectedFieldType = null;
        _fieldTypeController.clear();
      });
    } else if (value != null) {
      setState(() {
        _isCustomType = false;
        _selectedFieldType = value;
        _fieldTypeController.text = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetShell(
      title: widget.field == null ? 'Add Field' : 'Edit Field',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isCustomType)
              DropdownButtonFormField<String>(
                initialValue: _selectedFieldType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Field Type',
                ),
                items: commonFieldTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: _onFieldTypeChanged,
                validator: (value) {
                  if (value == null || value.isEmpty || value == 'Custom') {
                    return 'Please select a field type';
                  }
                  return null;
                },
              )
            else
              TextField(
                controller: _fieldTypeController,
                style: BitcoinTextStyle.body4(Bitcoin.black),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Field Type',
                  hintText: 'e.g., LinkedIn, Discord, etc.',
                ),
                textCapitalization: TextCapitalization.words,
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _fieldValueController,
              style: BitcoinTextStyle.body4(Bitcoin.black),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Value',
                hintText: 'Enter the field value',
              ),
              maxLines: null,
              keyboardType: TextInputType.multiline,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: BitcoinTextStyle.body5(Bitcoin.red),
              ),
            ],
            const SizedBox(height: 20),
            FooterButton(
              title: _isSaving ? 'Saving...' : 'Save',
              onPressed: _isSaving ? null : _saveField,
            ),
          ],
        ),
      ),
    );
  }
}
