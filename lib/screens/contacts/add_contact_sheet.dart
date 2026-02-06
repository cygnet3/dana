import 'dart:async';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/services/bip353_resolver.dart';
import 'package:danawallet/services/dana_address_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class AddContactSheet extends StatefulWidget {
  final Bip353Address? initialDanaAddress;
  final String? initialPaymentCode;

  const AddContactSheet({
    super.key,
    this.initialDanaAddress,
    this.initialPaymentCode,
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
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bip353AddressController.dispose();
    _paymentCodeController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  void _onDanaAddressChanged() {
    final query = _bip353AddressController.text.trim();
    final hasDanaAddress = query.isNotEmpty;
    setState(() {
      _hasDanaAddress = hasDanaAddress;
    });

    // If dana address is filled, clear SP address field
    if (hasDanaAddress) {
      _paymentCodeController.clear();
      _nameController.clear();
    }

    _searchDebounceTimer?.cancel();
    if (query.isEmpty) {
      setState(() {
        _remoteDanaAddresses = [];
        _isSearchingRemote = false;
      });
      return;
    }

    if (query.contains('@')) {
      setState(() {
        _remoteDanaAddresses = [];
        _isSearchingRemote = false;
      });
      return;
    }

    final searchPrefix = _extractSearchPrefix(query);
    if (searchPrefix.length < 3) {
      setState(() {
        _remoteDanaAddresses = [];
        _isSearchingRemote = false;
      });
      return;
    }

    // Debounce remote search to avoid too many API calls
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchRemoteAddresses(searchPrefix);
    });
  }

  String _extractSearchPrefix(String query) {
    final atIndex = query.indexOf('@');
    if (atIndex > 0) {
      return query.substring(0, atIndex).trim();
    }
    return query;
  }

  Future<void> _searchRemoteAddresses(String prefix) async {
    if (prefix.length < 3) return;

    final knownDanaAddresses =
        Provider.of<ContactsState>(context, listen: false)
            .getKnownBip353Addresses();

    setState(() {
      _isSearchingRemote = true;
    });

    try {
      final network = Provider.of<ChainState>(context, listen: false).network;
      final danaAddresses =
          await DanaAddressService(network: network).searchPrefix(prefix);

      if (mounted) {
        final newAddresses = danaAddresses
            .where((address) => !knownDanaAddresses.contains(address))
            .take(3)
            .toList();

        setState(() {
          _remoteDanaAddresses = newAddresses;
          _isSearchingRemote = false;
        });
      }
    } catch (e) {
      Logger().w('Failed to search remote addresses: $e');
      if (mounted) {
        setState(() {
          _remoteDanaAddresses = [];
          _isSearchingRemote = false;
        });
      }
    }
  }

  Future<String?> _resolveDanaAddress() async {
    final danaAddressString = _bip353AddressController.text.trim();
    if (danaAddressString.isEmpty) return null;

    setState(() {
      _errorMessage = null;
      _isResolving = true;
    });

    try {
      final network = Provider.of<ChainState>(context, listen: false).network;
      final parsed = Bip353Address.fromString(danaAddressString);
      final resolved = await Bip353Resolver.resolve(parsed, network);

      if (mounted && resolved != null) {
        setState(() {
          if (_nameController.text.trim().isEmpty) {
            _nameController.text = parsed.username;
          }
          _paymentCodeController.text = resolved;
          _isResolving = false;
        });
        return resolved;
      } else if (mounted) {
        setState(() {
          _errorMessage = 'Could not resolve SP address for this dana address';
          _isResolving = false;
        });
      }
    } catch (e) {
      Logger().w('Failed to resolve dana address: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to resolve dana address: $e';
          _isResolving = false;
        });
      }
    }
    return null;
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
        setState(() {
          _remoteDanaAddresses = [];
          _isSearchingRemote = false;
          _errorMessage = null;
        });

        _bip353AddressController.text = danaAddress.toString();
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = danaAddress.username;
        }
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
      });
      return;
    }

    // user filled in a dana address, but did not press search
    if (danaAddress != null && paymentCode.isEmpty) {
      final resolved = await _resolveDanaAddress();
      if (resolved == null) {
        setState(() {
          _isSaving = false;
        });
        return;
      }
      paymentCode = resolved;
      // show the user that we've resolved the sp-address
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final existingContact = contactsState.getContactByPaymentCode(paymentCode);
    if (existingContact != null) {
      if (mounted && danaAddress != null && existingContact.bip353Address == null) {
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
          Logger().e('Failed to update contact: $e');
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
      Logger().e('Failed to save contact: $e');
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
          builder: (context) => AlertDialog(
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
      builder: (context) => AlertDialog(
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
              'Add Contact',
              style: BitcoinTextStyle.title4(Bitcoin.black),
            ),
            const SizedBox(height: 20),
            // Name field
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
            // Dana address field
            TextField(
              controller: _bip353AddressController,
              style: BitcoinTextStyle.body4(Bitcoin.black),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Dana Address',
                hintText: 'user@domain.com',
                suffixIcon: _hasDanaAddress
                    ? IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _resolveDanaAddress,
                        tooltip: 'Resolve SP address',
                      )
                    : null,
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
            const SizedBox(height: 16),
            // Static address field
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
            // Save button
            FooterButton(
              title: _isSaving ? 'Saving...' : 'Save',
              onPressed: _isSaving ? null : _onSaveContact,
              isLoading: _isSaving,
              enabled: !_isSaving,
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
        ),
      ),
    );
  }
}
