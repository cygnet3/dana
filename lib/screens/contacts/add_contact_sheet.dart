import 'dart:async';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/extensions/string_display.dart';
import 'package:danawallet/generated/rust/api/validate.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/services/bip353_resolver.dart';
import 'package:danawallet/services/dana_address_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button_outlined.dart';
import 'package:danawallet/widgets/qr_code_scanner_widget.dart';
import 'package:danawallet/widgets/sheets/app_bottom_sheet_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool _isSaving = false;
  bool _isResolving = false;
  String? _errorMessage;

  // Confirmed address — set once user picks a Dana suggestion,
  // types a full dana address (auto-resolved), or pastes an SP address.
  String? _confirmedPaymentCode;
  Bip353Address? _confirmedDanaAddress;

  // Whether the SP fallback section is expanded.
  bool _showSpFallback = false;

  // Remote Dana suggestion state.
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

    // if a payment code has been provided, pre-fill it
    _confirmedPaymentCode = widget.initialPaymentCode;

    if (widget.initialDanaAddress != null) {
      // if a dana address has been provided, it has been confirmed already
      _confirmedDanaAddress = widget.initialDanaAddress;
      _nameController.text = widget.initialDanaAddress!.username;
    }

    _bip353AddressController.addListener(_onDanaAddressChanged);
    _nameController.addListener(() => setState(() {}));

    // if no other information has been provided, set the initial query
    if (widget.initialDanaQuery != null &&
        widget.initialDanaAddress == null &&
        widget.initialPaymentCode == null) {
      _bip353AddressController.text = widget.initialDanaQuery!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bip353AddressController.dispose();
    _searchDebounceTimer?.cancel();
    _autoResolveDebounceTimer?.cancel();
    super.dispose();
  }

  void _clearConfirmedAddress() {
    setState(() {
      _confirmedPaymentCode = null;
      _confirmedDanaAddress = null;
      _showSpFallback = false;
      _resetSearchState();
      _bip353AddressController.clear();
      _nameController.clear();
    });
  }

  void _onDanaAddressChanged() {
    final query = _bip353AddressController.text.trim();

    _searchDebounceTimer?.cancel();
    _autoResolveDebounceTimer?.cancel();

    setState(_resetSearchState);

    if (query.length < 3) return;

    if (query.contains('@')) {
      _autoResolveDebounceTimer =
          Timer(const Duration(milliseconds: 600), _resolveDanaAddress);
      return;
    }

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
          _confirmedDanaAddress = parsed;
          _confirmedPaymentCode = resolved;
          _remoteDanaAddresses = [];
          _nameController.text = parsed.username;
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
    final address = danaAddress.toString();
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Bitcoin.neutral4,
        child: Text(
          address[0].toUpperCase(),
          style:
              BitcoinTextStyle.body5(Bitcoin.white).apply(fontWeightDelta: 2),
        ),
      ),
      title: Text(address, style: BitcoinTextStyle.body5(Bitcoin.black)),
      onTap: () async {
        _searchDebounceTimer?.cancel();
        _autoResolveDebounceTimer?.cancel();
        setState(_resetSearchState);
        _bip353AddressController.text = address;
        FocusScope.of(context).unfocus();
        await _resolveDanaAddress();
      },
    );
  }

  Future<void> _onSaveContact() async {
    final paymentCode = _confirmedPaymentCode;
    if (paymentCode == null) return;

    final chainState = Provider.of<ChainState>(context, listen: false);
    final contactsState = Provider.of<ContactsState>(context, listen: false);

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _isSaving = false;
        _errorMessage = 'Name is required';
      });
      return;
    }

    final existingContact = contactsState.getContactByPaymentCode(paymentCode);
    if (existingContact != null) {
      if (mounted &&
          _confirmedDanaAddress != null &&
          existingContact.bip353Address == null) {
        final shouldUpdate = await showConfirmationAlertDialog(
          'Contact already exists',
          'This contact is already saved with the same static address. '
              'Do you want to add the Dana address (${_confirmedDanaAddress!}) to it?',
        );
        if (!shouldUpdate) {
          setState(() => _isSaving = false);
          return;
        }
        try {
          await contactsState.updateContact(Contact(
            id: existingContact.id,
            name: existingContact.name ?? name,
            bip353Address: _confirmedDanaAddress,
            paymentCode: existingContact.paymentCode,
          ));
          if (mounted) Navigator.pop(context, true);
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
        showAlertDialog('Contact already exists',
            'This contact is already saved with the same static address.');
      }
      setState(() => _isSaving = false);
      return;
    }

    try {
      await contactsState.addContact(
        paymentCode: paymentCode,
        danaAddress: _confirmedDanaAddress,
        network: chainState.network,
        name: name,
      );
      if (mounted) Navigator.pop(context, true);
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

  /// Validates a pasted/scanned SP address and, if valid, confirms it. Shows an
  /// inline error otherwise so the confirmation card never reflects bad input.
  void _confirmPaymentCode(String code) {
    if (code.isEmpty) return;

    final network = Provider.of<ChainState>(context, listen: false).network;
    try {
      validateAddressWithNetwork(address: code, network: network);
      if (!isReusablePaymentCode(address: code)) {
        throw Exception('Non-reusable payment info not allowed');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Not a valid silent payment address');
      return;
    }

    setState(() {
      _confirmedPaymentCode = code;
      _confirmedDanaAddress = null;
      _errorMessage = null;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    _confirmPaymentCode(data?.text?.trim() ?? '');
  }

  Future<void> _scanQrCode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QRCodeScannerWidget()),
    );
    if (!mounted) return;
    _confirmPaymentCode(result?.trim() ?? '');
  }

  Widget _buildDanaSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _bip353AddressController,
          style: BitcoinTextStyle.body4(Bitcoin.black),
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Dana address',
            hintText: 'user@domain.com',
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
          ),
        ),
        if (_bip353AddressController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          if (_isSearchingRemote && _remoteDanaAddresses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text('Searching...',
                  style: BitcoinTextStyle.body5(Bitcoin.neutral6)),
            ),
          if (_remoteDanaAddresses.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _remoteDanaAddresses.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, i) =>
                    _buildDanaAddressSuggestionItem(_remoteDanaAddresses[i]),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildSpFallbackSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        FooterButtonOutlined(
          title: 'Paste from clipboard',
          onPressed: _pasteFromClipboard,
        ),
        const SizedBox(height: 8),
        FooterButtonOutlined(
          title: 'Scan QR code',
          onPressed: _scanQrCode,
        ),
      ],
    );
  }

  Widget _buildConfirmedAddressCard() {
    final isDana = _confirmedDanaAddress != null;
    final displayLabel = isDana
        ? _confirmedDanaAddress!.toString()
        : _confirmedPaymentCode!.truncated(maxFullLength: 24);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Bitcoin.neutral2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Bitcoin.neutral4),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Bitcoin.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayLabel,
                    style: BitcoinTextStyle.body5(Bitcoin.black)),
                if (isDana)
                  Text('SP address resolved',
                      style: BitcoinTextStyle.body5(Bitcoin.neutral6)),
              ],
            ),
          ),
          // if a code has been provided, hide the edit button
          if (widget.initialPaymentCode == null)
            TextButton(
              onPressed: _clearConfirmedAddress,
              child:
                  Text('Change', style: BitcoinTextStyle.body5(Bitcoin.orange)),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDanaSearchSection(),
        const SizedBox(height: 12),
        if (_showSpFallback)
          _buildSpFallbackSection()
        else
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showSpFallback = true),
              child: Text(
                "Can't find them on Dana?",
                style: BitcoinTextStyle.body5(Bitcoin.neutral6),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildConfirmedView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConfirmedAddressCard(),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          style: BitcoinTextStyle.body4(Bitcoin.black),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Name',
            hintText: 'e.g. Alice',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConfirmed = _confirmedPaymentCode != null;
    final canSave =
        isConfirmed && !_isSaving && _nameController.text.trim().isNotEmpty;

    return AppBottomSheetShell(
      title: 'Add contact',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isConfirmed ? _buildConfirmedView() : _buildSearchView(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: BitcoinTextStyle.body5(Bitcoin.red)),
            ],
            const SizedBox(height: 20),
            FooterButton(
              title: _isSaving ? 'Saving...' : 'Add contact',
              onPressed: canSave ? _onSaveContact : null,
              isLoading: _isSaving,
              enabled: canSave,
            ),
          ],
        ),
      ),
    );
  }
}
