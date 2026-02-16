import 'dart:async';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/screens/onboarding/onboarding_skeleton.dart';
import 'package:danawallet/services/dana_address_service.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button_outlined.dart';
import 'package:danawallet/widgets/loading_widget.dart';
import 'package:danawallet/widgets/pin_guard.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

class RegisterDanaAddressScreen extends StatefulWidget {
  const RegisterDanaAddressScreen({
    super.key,
  });

  @override
  State<RegisterDanaAddressScreen> createState() =>
      _RegisterDanaAddressScreenState();
}

class _RegisterDanaAddressScreenState extends State<RegisterDanaAddressScreen> {
  static const int _minUsernameLength = 3;
  static const int _maxUsernameLength = 30;
  static const Duration _debounceDuration = Duration(milliseconds: 500);

  // Reserved usernames that cannot be registered
  static const List<String> _reservedNames = [
    'admin',
    'administrator',
    'support',
    'help',
    'info',
    'root',
    'system',
    'api',
    'www',
    'mail',
    'ftp',
    'postmaster',
    'hostmaster',
    'webmaster',
    'bitcoin',
    'satoshi',
    'dana',
    'official',
    'security',
    'abuse',
    'noreply',
    'no-reply',
    'donate',
  ];

  final TextEditingController _customUsernameController =
      TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;
  bool _isCheckingAvailability = false;
  bool? _isCustomUsernameAvailable;
  bool _isRegistering = false;
  String? _customUsername;
  String? _validationError;
  bool _hasUserEdited = false;
  String? _suggestedUsername;
  String? _domain;
  DanaAddressService? _danaAddressService;

  @override
  void initState() {
    super.initState();

    // Add focus listener
    _focusNode.addListener(_onFocusChange);

    // initialize username and domain
    loadUsernameAndDomain();
  }

  Future<void> loadUsernameAndDomain() async {
    final walletState = Provider.of<WalletState>(context, listen: false);
    final addressService = DanaAddressService(network: walletState.network);

    while (true) {
      try {
        final suggestedUsername = await walletState.createSuggestedUsername();
        final domain = await addressService.danaAddressDomain;

        setState(() {
          _danaAddressService = addressService;
          _suggestedUsername = suggestedUsername;
          _domain = domain;
        });
        return;
      } catch (e) {
        displayError("Failed to read domain", e);
      }
      // keep trying if we have no internet connection
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // When field gains focus, clear it if it contains the suggested username
      if (!_hasUserEdited &&
          _suggestedUsername != null &&
          _customUsernameController.text == _suggestedUsername) {
        _customUsernameController.clear();
      }
    } else {
      // When field loses focus, restore suggested username if empty
      if (_customUsernameController.text.isEmpty &&
          _suggestedUsername != null) {
        _customUsernameController.text = _suggestedUsername!;
        _hasUserEdited = false;
        setState(() {
          _customUsername = null;
          _isCustomUsernameAvailable = null;
          _validationError = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.dispose();
    _customUsernameController.dispose();
    super.dispose();
  }

  /// Validates username format and returns error message if invalid
  ///
  /// Username must:
  /// - Be 3-30 characters long
  /// - Contain only lowercase letters, numbers, hyphens, periods, and underscores
  /// - Start and end with alphanumeric characters
  /// - Not contain consecutive or mixed special characters
  /// - Not be a reserved name
  ///
  /// This ensures DNS compatibility and BIP353 compliance
  String? _validateUsername(String username) {
    // Normalize to lowercase for validation
    final cleaned = username.trim().toLowerCase();

    // Check minimum length
    if (cleaned.length < _minUsernameLength) {
      return 'Dana address must be at least $_minUsernameLength characters';
    }

    // Check maximum length
    if (cleaned.length > _maxUsernameLength) {
      return 'Dana address must be $_maxUsernameLength characters or less';
    }

    // Check DNS-safe characters: letters, numbers, hyphens, and periods
    // Allow underscores as they're common in usernames and supported in DNS labels
    final dnsRegex = RegExp(r'^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$');
    if (!dnsRegex.hasMatch(cleaned)) {
      if (cleaned.startsWith('-') || cleaned.endsWith('-')) {
        return 'Dana address cannot start or end with a hyphen';
      }
      if (cleaned.startsWith('.') || cleaned.endsWith('.')) {
        return 'Dana address cannot start or end with a period';
      }
      if (cleaned.startsWith('_') || cleaned.endsWith('_')) {
        return 'Dana address cannot start or end with an underscore';
      }
      if (cleaned.contains(' ')) {
        return 'Dana address cannot contain spaces';
      }
      return 'Dana address can only contain letters, numbers, hyphens, periods, and underscores';
    }

    // Check for consecutive special characters
    if (cleaned.contains('--') ||
        cleaned.contains('..') ||
        cleaned.contains('__')) {
      return 'Dana address cannot contain consecutive special characters';
    }

    // Check for mixed consecutive special characters
    if (cleaned.contains('.-') ||
        cleaned.contains('-.') ||
        cleaned.contains('._') ||
        cleaned.contains('_.') ||
        cleaned.contains('_-') ||
        cleaned.contains('-_')) {
      return 'Dana address cannot mix special characters';
    }

    // Check reserved names
    if (_reservedNames.contains(cleaned)) {
      return 'Dana address "$cleaned" is reserved';
    }

    return null; // Valid
  }

  void _onUsernameChanged(String value) {
    // Cancel any pending debounce timer
    _debounceTimer?.cancel();

    final username = value.trim();

    // Handle empty input
    if (username.isEmpty || _domain == null) {
      setState(() {
        _isCustomUsernameAvailable = null;
        _customUsername = null;
        _validationError = null;
        _isCheckingAvailability = false;
      });
      return;
    }

    // Normalize to lowercase for consistency
    final normalized = username.toLowerCase();

    // Validate username format
    final validationError = _validateUsername(normalized);
    if (validationError != null) {
      setState(() {
        _customUsername = normalized;
        _isCustomUsernameAvailable = null;
        _validationError = validationError;
        _isCheckingAvailability = false;
      });
      return;
    }

    // Clear validation error and set username
    setState(() {
      _customUsername = normalized;
      _validationError = null;
      _isCheckingAvailability = false;
    });

    // Debounce: wait for user to stop typing before checking availability
    _debounceTimer = Timer(_debounceDuration, () {
      _checkAvailability(normalized);
    });
  }

  Future<void> _checkAvailability(String username) async {
    setState(() {
      _isCheckingAvailability = true;
    });

    try {
      final isAvailable =
          await _danaAddressService!.isDanaUsernameAvailable(username);
      if (mounted && _customUsername == username) {
        setState(() {
          _isCustomUsernameAvailable = isAvailable;
          _isCheckingAvailability = false;
        });
      }
    } catch (e) {
      Logger().e('Error checking availability: $e');
      if (mounted && _customUsername == username) {
        setState(() {
          _isCustomUsernameAvailable = null;
          _isCheckingAvailability = false;
        });
      }
    }
  }

  Future<void> _onRegister() async {
    final walletState = Provider.of<WalletState>(context, listen: false);
    final contactsState = Provider.of<ContactsState>(context, listen: false);
    // Determine which username to use (from the text field)
    final currentText = _customUsernameController.text.trim();
    final rawUsername =
        currentText.isNotEmpty ? currentText : _suggestedUsername;

    if (rawUsername == null || rawUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Dana address available to register')),
      );
      return;
    }

    // Normalize username to lowercase before registration
    final usernameToRegister = rawUsername.toLowerCase();

    // Validate the username one more time before registration
    final validationError = _validateUsername(usernameToRegister);
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid username: $validationError')),
      );
      return;
    }

    setState(() {
      _isRegistering = true;
    });

    try {
      await walletState.registerDanaAddress(usernameToRegister);

      if (!mounted) return;

      // Registration successful - address is already saved by registerDanaAddress
      final registeredAddress = walletState.danaAddress;
      if (registeredAddress != null) {
        Logger().i('Registration successful: $registeredAddress');

        // Persist the dana address to storage (already done by registerDanaAddress, but ensure consistency)
        await WalletRepository.instance.saveDanaAddress(registeredAddress);

        // Set the dana address for the 'you' user
        contactsState.setYouContactDanaAddress(registeredAddress);

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const PinGuard()),
            (Route<dynamic> route) => false,
          );
        }
      } else {
        throw Exception('Registration succeeded but dana address is null');
      }
    } catch (e) {
      displayError('Failed to register username', e);
      setState(() {
        _isRegistering = false;
      });
    }
  }

  void _onSkip() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const PinGuard()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // if we're still loading, show an indicator
    if (_domain == null) {
      return const LoadingWidget();
    }

    // Determine which username will be registered
    final finalUsername = _customUsername?.isNotEmpty == true
        ? _customUsername
        : _suggestedUsername;
    final finalDanaAddress =
        (finalUsername != null) ? '$finalUsername@$_domain' : null;

    final body = SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: Adaptive.h(4)),

          // Blue circle with white person silhouette
          Container(
            width: Adaptive.h(12),
            height: Adaptive.h(12),
            decoration: const BoxDecoration(
              color: danaBlue,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              size: Adaptive.h(8),
              color: Bitcoin.white,
            ),
          ),

          SizedBox(height: Adaptive.h(3)),

          // "Here's your Dana address" title
          AutoSizeText(
            'Choose your Dana address',
            style: BitcoinTextStyle.title3(Bitcoin.black).copyWith(
                fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 26),
            maxLines: 1,
            textAlign: TextAlign.center,
          ),

          SizedBox(height: Adaptive.h(4)),

          // Text field with availability indicator
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Text field (full width)
              TextField(
                controller: _customUsernameController,
                focusNode: _focusNode,
                style: BitcoinTextStyle.body4(Bitcoin.black),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Your Dana address',
                  hintText: _suggestedUsername ?? 'my.custom_address',
                  helperText:
                      'Letters, numbers, hyphens, periods, and underscores',
                  errorText: _validationError,
                ),
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                keyboardType: TextInputType.text,
                onChanged: (value) {
                  // Mark that user has edited, or reset if field is now empty
                  if (value.isEmpty) {
                    setState(() {
                      _hasUserEdited = false;
                      _customUsername = null;
                      _isCustomUsernameAvailable = null;
                      _validationError = null;
                    });
                    return;
                  } else if (!_hasUserEdited && value.isNotEmpty) {
                    setState(() {
                      _hasUserEdited = true;
                    });
                  }

                  // Convert to lowercase in real-time
                  final lowercase = value.toLowerCase();
                  if (value != lowercase) {
                    final selection = _customUsernameController.selection;
                    _customUsernameController.value = TextEditingValue(
                      text: lowercase,
                      selection: selection,
                    );
                  }
                  _onUsernameChanged(lowercase);
                },
              ),

              // Availability indicator below text field (only show if user has edited and it's different from suggested)
              if (_hasUserEdited &&
                  _customUsername?.isNotEmpty == true &&
                  _customUsername != _suggestedUsername &&
                  _validationError == null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: _isCheckingAvailability
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : _isCustomUsernameAvailable == true
                              ? Icon(Icons.check_circle,
                                  color: Bitcoin.green, size: 24)
                              : _isCustomUsernameAvailable == false
                                  ? Icon(Icons.cancel,
                                      color: Bitcoin.red, size: 24)
                                  : Icon(Icons.help_outline,
                                      color: Bitcoin.neutral6, size: 24),
                    ),
                    const SizedBox(width: 8),
                    AutoSizeText(
                      _isCheckingAvailability
                          ? 'Checking availability...'
                          : _isCustomUsernameAvailable == true
                              ? 'This address is available'
                              : _isCustomUsernameAvailable == false
                                  ? 'This address is already taken'
                                  : 'Checking...',
                      style: BitcoinTextStyle.body2(_isCheckingAvailability
                              ? Bitcoin.neutral6
                              : _isCustomUsernameAvailable == true
                                  ? Bitcoin.green
                                  : _isCustomUsernameAvailable == false
                                      ? Bitcoin.red
                                      : Bitcoin.neutral6)
                          .copyWith(fontSize: 12),
                      maxLines: 1,
                    ),
                  ],
                ),
              ],
            ],
          ),

          SizedBox(height: Adaptive.h(4)),

          // "Your Dana address will be" at the bottom
          AutoSizeText(
            'Your Dana address will be',
            style: BitcoinTextStyle.body3(Bitcoin.neutral6)
                .copyWith(fontFamily: 'Inter', fontWeight: FontWeight.w400),
            maxLines: 1,
            textAlign: TextAlign.center,
          ),

          SizedBox(height: Adaptive.h(2)),

          // Display current dana address (custom if entered, otherwise suggested)
          if (finalDanaAddress != null)
            Bip353Address.fromString(finalDanaAddress).asRichText(17.0)
          else
            AutoSizeText(
              'No Dana address available',
              style: BitcoinTextStyle.body2(Bitcoin.neutral6),
              maxLines: 1,
              textAlign: TextAlign.center,
            ),

          SizedBox(height: Adaptive.h(4)),

          // BIP353 info block
          GestureDetector(
            onTap: () async {
              final url = Uri.parse(
                  'https://bitcoin.design/guide/how-it-works/human-readable-addresses/');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Bitcoin.neutral2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Bitcoin.neutral7,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: BitcoinTextStyle.body2(Bitcoin.neutral7)
                            .copyWith(fontSize: 11),
                        children: [
                          const TextSpan(
                              text: 'Dana addresses are using BIP353, '),
                          TextSpan(
                            text: 'click here to know more',
                            style:
                                BitcoinTextStyle.body2(Bitcoin.blue).copyWith(
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Extra bottom padding for keyboard clearance
          SizedBox(height: Adaptive.h(10)),
        ],
      ),
    );

    // Determine if button should be enabled
    // Button is enabled when:
    // 1. No validation error
    // 2. Either using suggested username (not edited, empty field, or text matches suggested),
    //    OR custom username is available
    final currentText = _customUsernameController.text.trim();
    final isUsingSuggested = !_hasUserEdited ||
        currentText.isEmpty ||
        currentText == _suggestedUsername;
    final isButtonEnabled = _validationError == null &&
        _domain != null &&
        (isUsingSuggested || _isCustomUsernameAvailable == true);

    final skipButton = FooterButtonOutlined(title: 'Skip', onPressed: _onSkip);

    final registerButton = FooterButton(
      title: 'Register',
      onPressed: _onRegister,
      isLoading: _isRegistering,
      enabled: isButtonEnabled && !_isRegistering,
    );

    final Widget footer;
    if (isDevEnv) {
      footer = Column(children: [
        skipButton,
        SizedBox(height: Adaptive.h(2)),
        registerButton,
      ]);
    } else {
      footer = registerButton;
    }

    return PopScope(
      canPop: false,
      child: OnboardingSkeleton(
        body: body,
        footer: footer,
      ),
    );
  }
}
