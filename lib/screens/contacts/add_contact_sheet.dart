import 'dart:async';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/extensions/string_display.dart';
import 'package:danawallet/generated/rust/api/validate.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/services/bip353_resolver.dart';
import 'package:danawallet/services/dana_address_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/sheets/app_bottom_sheet_shell.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class AddContactSheet extends StatefulWidget {
  final Bip353Address? initialDanaAddress;
  final String? initialPaymentCode;

  /// Pre-fills the Dana search field with an arbitrary string (e.g. a partial
  /// username typed in ChooseRecipientScreen). Ignored when [initialDanaAddress]
  /// or [initialPaymentCode] is also provided.
  final String? initialDanaQuery;

  const AddContactSheet({
    super.key,
    this.initialDanaAddress,
    this.initialPaymentCode,
    this.initialDanaQuery,
  });

  @override
  State<AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<AddContactSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bip353AddressController =
      TextEditingController();
  final TextEditingController _paymentCodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isResolving = false;
  String? _errorMessage;
  bool _hasDanaAddress = false;
  List<Bip353Address> _remoteDanaAddresses = [];
  bool _isSearchingRemote = false;
  Timer? _searchDebounceTimer;
  Timer? _autoResolveDebounceTimer;

  static final _log = Logger();

  void _resetSearchState() {
    _remoteDanaAddresses = [];
    _isSearchingRemote = false;
    _errorMessage = null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialDanaAddress != null) {
      _bip353AddressController.text = widget.initialDanaAddress!.toString();
      _nameController.text = widget.initialDanaAddress!.username;
      _hasDanaAddress = true;
    }
    if (widget.initialPaymentCode != null) {
      _paymentCodeController.text = widget.initialPaymentCode!;
    }
    _bip353AddressController.addListener(_onDanaAddressChanged);

    // Automatically resolve SP address if dana address is provided but SP address is not
    if (widget.initialDanaAddress != null &&
        (widget.initialPaymentCode == null ||
            widget.initialPaymentCode!.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resolveDanaAddress();
      });
    } else if (widget.initialDanaQuery != null &&
        widget.initialDanaAddress == null &&
        widget.initialPaymentCode == null) {
      _bip353AddressController.text = widget.initialDanaQuery!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bip353AddressController.dispose();
    _paymentCodeController.dispose();
    _searchDebounceTimer?.cancel();
    _autoResolveDebounceTimer?.cancel();
    super.dispose();
  }

  void _onDanaAddressChanged() {
    final query = _bip353AddressController.text.trim();

    _searchDebounceTimer?.cancel();
    _autoResolveDebounceTimer?.cancel();

    setState(() {
      _hasDanaAddress = query.isNotEmpty;
      _resetSearchState();
    });

    if (query.isEmpty) return;

    if (query.contains('@')) {
      _autoResolveDebounceTimer =
          Timer(const Duration(milliseconds: 600), _resolveDanaAddress);
      return;
    }

    if (query.length < 3) return;

    _searchDebounceTimer = Timer(
      const Duration(milliseconds: 500),
      () => _searchRemoteAddresses(query),
    );
  }

  Future<void> _searchRemoteAddresses(String prefix) async {
    final knownDanaAddresses =
        Provider.of<ContactsState>(context, listen: false)
            .getKnownBip353Addresses();

    setState(() => _isSearchingRemote = true);

    try {
      final network = Provider.of<ChainState>(context, listen: false).network;
      final results =
          await DanaAddressService(network: network).searchPrefix(prefix);

      if (!mounted) return;

      final filtered = results
          .where((a) => !knownDanaAddresses.contains(a))
          .take(3)
          .toList();

      setState(() {
        _remoteDanaAddresses = filtered;
        _isSearchingRemote = false;
      });
    } catch (e) {
      _log.w('Failed to search remote addresses: $e');
      if (mounted) setState(() => _isSearchingRemote = false);
    }
  }

  Future<void> _resolveDanaAddress() async {
    final danaAddressString = _bip353AddressController.text.trim();
    if (danaAddressString.isEmpty) return;

    setState(() {
      _errorMessage = null;
      _isResolving = true;
    });

    try {
      final network = Provider.of<ChainState>(context, listen: false).network;
      final parsed = Bip353Address.fromString(danaAddressString);
      final resolved = await Bip353Resolver.resolve(parsed, network);

      if (!mounted) return;

      if (resolved != null) {
        setState(() {
          if (_nameController.text.trim().isEmpty) {
            _nameController.text = parsed.username;
          }
          _paymentCodeController.text = resolved;
          _isResolving = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Could not resolve SP address for this Dana address';
          _isResolving = false;
        });
      }
    } catch (e) {
      _log.w('Failed to resolve Dana address: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to resolve Dana address: $e';
          _isResolving = false;
        });
      }
    }
  }

  Widget _buildDanaAddressSuggestionItem(Bip353Address danaAddress) {
    final initial = danaAddress.toString()[0].toUpperCase();
    const avatarColor = Colors.grey;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: avatarColor,
        child: Text(
          initial,
          style:
              BitcoinTextStyle.body5(Bitcoin.white).apply(fontWeightDelta: 2),
        ),
      ),
      title: Text(
        danaAddress.toString(),
        style: BitcoinTextStyle.body5(Bitcoin.black),
      ),
      onTap: () async {
        _searchDebounceTimer?.cancel();
        _autoResolveDebounceTimer?.cancel();
        setState(_resetSearchState);
        _bip353AddressController.text = danaAddress.toString();
        FocusScope.of(context).unfocus();
        await _resolveDanaAddress();
      },
    );
  }

  Future<void> _onSaveContact() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final walletState = Provider.of<WalletState>(context, listen: false);
    final contactsState = Provider.of<ContactsState>(context, listen: false);

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final danaAddressString = _bip353AddressController.text.trim();
    String paymentCode = _paymentCodeController.text.trim();

    // Validation: at least dana address OR static address must be filled, and name must be filled
    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'Name is required';
        _isSaving = false;
      });
      return;
    }

    Bip353Address? danaAddress;
    if (danaAddressString.isNotEmpty) {
      try {
        danaAddress = Bip353Address.fromString(danaAddressString);
      } catch (e) {
        setState(() {
          _errorMessage = e.toString();
          _isSaving = false;
        });
      }
    }

    if (danaAddress == null && paymentCode.isEmpty) {
      setState(() {
        _errorMessage =
            'Either dana address or static address must be provided';
        _isSaving = false;
      });
      return;
    }

    // user filled in a dana address, but resolution has not finished yet
    if (danaAddress != null && paymentCode.isEmpty) {
      await _resolveDanaAddress();
      paymentCode = _paymentCodeController.text.trim();
      if (paymentCode.isEmpty) {
        setState(() => _isSaving = false);
        return;
      }
      // show the user that we've resolved the sp-address
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final existingContact = contactsState.getContactByPaymentCode(paymentCode);
    if (existingContact != null) {
      if (mounted &&
          danaAddress != null &&
          existingContact.bip353Address == null) {
        final shouldUpdate = await _showUpdateExistingContactDialog(
          existingContact,
          danaAddress,
        );
        if (!shouldUpdate) {
          setState(() {
            _isSaving = false;
          });
          return;
        }
        try {
          final updatedContact = Contact(
            id: existingContact.id,
            name: existingContact.name ?? name,
            bip353Address: danaAddress,
            paymentCode: existingContact.paymentCode,
          );
          await contactsState.updateContact(updatedContact);
          if (mounted) {
            Navigator.pop(context, true);
          }
          return;
        } catch (e) {
          _log.e('Failed to update contact: $e');
          if (mounted) {
            setState(() {
              _isSaving = false;
              _errorMessage = 'Failed to update contact: $e';
            });
          }
          return;
        }
      }

      if (mounted) {
        await _showContactAlreadyExistsDialog();
      }
      setState(() {
        _isSaving = false;
      });
      return;
    }

    try {
      final network = walletState.network;

      await contactsState.addContact(
        paymentCode: paymentCode,
        danaAddress: danaAddress,
        network: network,
        name: name.isNotEmpty ? name : null,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _log.e('Failed to save contact: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save contact: $e';
        });
      }
    }
  }

  Future<bool> _showUpdateExistingContactDialog(
      Contact existingContact, Bip353Address danaAddress) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Contact already exists'),
            content: Text(
              'This contact is already saved with the same static address. '
              'Do you want to add the Dana address (${danaAddress.toString()}) to it?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Update'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showContactAlreadyExistsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Contact already exists'),
        content: const Text(
          'This contact is already saved with the same static address.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildDanaSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _bip353AddressController,
          style: BitcoinTextStyle.body4(Bitcoin.black),
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Dana Address',
            hintText: 'user@domain.com',
          ),
        ),
        if (_bip353AddressController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          if (_isSearchingRemote && _remoteDanaAddresses.isEmpty)
            Text(
              'Searching...',
              style: BitcoinTextStyle.body5(Bitcoin.neutral6),
            ),
          if (_remoteDanaAddresses.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _remoteDanaAddresses.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  return _buildDanaAddressSuggestionItem(
                      _remoteDanaAddresses[index]);
                },
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetShell(
      title: 'Add Contact',
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                style: BitcoinTextStyle.body4(Bitcoin.black),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Name',
                  hintText: 'Contact name',
                ),
              ),
              const SizedBox(height: 16),
              _buildDanaSearchSection(),
              const SizedBox(height: 16),
              TextField(
                controller: _paymentCodeController,
                style: BitcoinTextStyle.body4(
                  (_hasDanaAddress || _isResolving)
                      ? Bitcoin.neutral6
                      : Bitcoin.black,
                ),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Static Address (SP)',
                  hintText:
                      _hasDanaAddress ? 'Resolved from dana address' : 'sp1q...',
                  suffixIcon: _isResolving
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  filled: _hasDanaAddress,
                  fillColor: _hasDanaAddress ? Bitcoin.neutral2 : null,
                ),
                readOnly: _hasDanaAddress || _isResolving,
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
                onPressed: _isSaving ? null : _onSaveContact,
                isLoading: _isSaving,
                enabled: !_isSaving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
