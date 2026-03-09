# Dana Wallet Coding Standards

> Comprehensive coding conventions and best practices for Dana wallet development in both Dart and Rust.

## Table of Contents

- [Overview](#overview)
- [Dart/Flutter Standards](#dartflutter-standards)
- [Rust Standards](#rust-standards)
- [Cross-Language Patterns](#cross-language-patterns)
- [Documentation Standards](#documentation-standards)
- [Quick Reference](#quick-reference)

---

## Overview

This document defines the coding standards used in the Dana wallet project. These conventions ensure:

- **Consistency** across the codebase
- **Readability** for new contributors
- **Maintainability** as the project grows
- **LLM-friendliness** for AI-assisted development

**Guiding Principle:** Code should be **self-documenting** through clear naming and structure. Comments are used strategically, not extensively.

---

## Dart/Flutter Standards

### File Naming Conventions

All Dart files use **snake_case** with descriptive suffixes:

| Suffix | Purpose | Example |
|--------|---------|---------|
| `_screen.dart` | Full-screen components | `wallet_settings_screen.dart` |
| `_widget.dart` | Reusable UI widgets | `connection_status_widget.dart` |
| `_state.dart` | State management classes | `wallet_state.dart` |
| `_service.dart` | Business logic services | `pin_service.dart` |
| `_repository.dart` | Data persistence | `wallet_repository.dart` |
| `_model.dart` | Data models | `contact_model.dart` |
| `_skeleton.dart` | Layout templates | `onboarding_skeleton.dart` |

**Examples from codebase:**
```
✅ lib/screens/settings/wallet_settings_screen.dart
✅ lib/repositories/contacts_repository.dart
✅ lib/states/wallet_state.dart
✅ lib/services/pin_service.dart
✅ lib/widgets/buttons/footer/footer_button.dart
```

### Class & Type Naming

#### Classes: PascalCase

```dart
✅ class WalletState extends ChangeNotifier { }
✅ class Contact { }
✅ class PinService { }
✅ class FooterButton extends StatelessWidget { }

❌ class wallet_state { }
❌ class contactModel { }
```

#### Functions & Variables: camelCase

```dart
✅ Future<void> registerDanaAddress(String username) { }
✅ void displayNotification(String text) { }
✅ final globalNavigatorKey = GlobalKey<NavigatorState>();

❌ Future<void> RegisterDanaAddress(String username) { }
❌ void display_notification(String text) { }
```

#### Private Members: Leading Underscore

```dart
✅ class WalletRepository {
  WalletRepository._();  // Private constructor
  
  Future<void> _updateWalletState() { }  // Private method
  String? _addressErrorText;  // Private field
}

❌ WalletRepository.private();
```

#### Constants: camelCase or SCREAMING_SNAKE_CASE

```dart
// Prefer camelCase for most constants
✅ const String defaultMainnet = "https://...";
✅ const int defaultDustLimit = 600;
✅ const Color danaBlue = Color.fromARGB(255, 10, 109, 214);

// Use SCREAMING_SNAKE_CASE for true constant identifiers
✅ const String KEY_SCAN_SK = "scansk";
```

### Import Organization

Organize imports in **3 sections**, separated by blank lines:

1. **Dart core imports** (`dart:*`)
2. **External package imports** (`package:` from pubspec.yaml)
3. **Internal app imports** (`package:danawallet/*`)

**Example from `main.dart`:**

```dart
// 1. Dart core imports
import 'dart:io';

// 2. External packages
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';

// 3. Internal app imports
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/enums/network.dart';
import 'package:danawallet/generated/rust/frb_generated.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/wallet_state.dart';
```

**Rules:**
- ✅ Use absolute package imports (never relative imports)
- ✅ Sort alphabetically within each section (optional but nice)
- ✅ Separate sections with blank lines
- ❌ Never mix import types

### Code Organization Patterns

#### 1. Singleton Pattern (Repositories & Services)

Used for repositories and stateless services that should have only one instance:

```dart
✅ class WalletRepository {
  // Private constructor
  WalletRepository._();
  
  // Singleton instance
  static final instance = WalletRepository._();
  
  // Public API
  Future<void> saveScanSk(ApiScanKey scanKey) async {
    // Implementation
  }
}

// Usage
await WalletRepository.instance.saveScanSk(scanKey);
```

**Used in:**
- All repositories (`*_repository.dart`)
- `PinService`
- Database helpers

#### 2. Factory Constructor Pattern (State Management)

Used for state classes that need async initialization:

```dart
✅ class WalletState extends ChangeNotifier {
  // Private constructor
  WalletState._();
  
  // Async factory constructor
  static Future<WalletState> create() async {
    final instance = WalletState._();
    await instance._initStreams();
    await instance._loadInitialData();
    return instance;
  }
  
  Future<void> _initStreams() async {
    // Initialization logic
  }
}

// Usage
final walletState = await WalletState.create();
```

**Used in:**
- `WalletState`
- `ChainState`
- Other stateful providers

#### 3. Enum with Extensions

Enums should include helper methods for conversions and display:

```dart
✅ enum Network {
  mainnet,
  testnet,
  signet,
  regtest;
  
  // String conversion
  @override
  String toString() {
    switch (this) {
      case Network.mainnet:
        return "mainnet";
      case Network.testnet:
        return "testnet";
      case Network.signet:
        return "signet";
      case Network.regtest:
        return "regtest";
    }
  }
  
  // Getters for related data
  String get defaultBlindbitUrl {
    switch (this) {
      case Network.mainnet:
        return defaultMainnet;
      case Network.testnet:
        return defaultTestnet;
      // ...
    }
  }
  
  // Color coding
  Color get toColor {
    switch (this) {
      case Network.mainnet:
        return Colors.orange;
      case Network.testnet:
        return Colors.green;
      // ...
    }
  }
  
  // Parse from string
  static Network fromString(String network) {
    switch (network) {
      case "mainnet":
        return Network.mainnet;
      case "testnet":
        return Network.testnet;
      // ...
      default:
        throw Exception("Unknown network: $network");
    }
  }
}
```

**Files:** `lib/data/enums/*.dart`

#### 4. Data Models with Serialization

Data models should include `toMap()` and `fromMap()` for persistence:

```dart
✅ class Contact {
  final String paymentCode;
  final String? danaAddress;
  final String? nym;
  
  Contact({
    required this.paymentCode,
    this.danaAddress,
    this.nym,
  });
  
  // Serialize to Map (for database/JSON)
  Map<String, dynamic> toMap() {
    return {
      'payment_code': paymentCode,
      'dana_address': danaAddress,
      'nym': nym,
    };
  }
  
  // Deserialize from Map
  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      paymentCode: map['payment_code'] as String,
      danaAddress: map['dana_address'] as String?,
      nym: map['nym'] as String?,
    );
  }
}
```

**Files:** `lib/data/models/*.dart`

#### 5. Screen Skeleton Pattern

Reusable layout templates for consistent screen structure:

```dart
✅ class OnboardingSkeleton extends StatelessWidget {
  final Widget body;
  final Widget footer;
  
  const OnboardingSkeleton({
    super.key,
    required this.body,
    required this.footer,
  });
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: body),
            footer,
          ],
        ),
      ),
    );
  }
}

// Usage
OnboardingSkeleton(
  body: OnboardingContent(),
  footer: ContinueButton(),
)
```

**Benefits:**
- Consistent layouts across features
- Easy to update all screens at once
- Reduces code duplication

### Widget Best Practices

#### Prefer StatelessWidget

Use `StatelessWidget` when possible; only use `StatefulWidget` when you need:
- Local state (not global state)
- Lifecycle methods (`initState`, `dispose`)
- Animation controllers

```dart
✅ class FooterButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  
  const FooterButton({
    super.key,
    required this.text,
    required this.onPressed,
  });
  
  @override
  Widget build(BuildContext context) { ... }
}

❌ class FooterButton extends StatefulWidget {
  // No state needed - should be StatelessWidget
}
```

#### Use const Constructors

Use `const` for widgets that don't depend on runtime values:

```dart
✅ const SizedBox(height: 16)
✅ const Text("Hello")
✅ const Icon(Icons.wallet)

❌ SizedBox(height: 16)  // Missing const
```

#### Required vs Optional Parameters

```dart
✅ class FooterButton extends StatelessWidget {
  // Required parameters
  final String text;
  final VoidCallback onPressed;
  
  // Optional parameters with defaults
  final bool enabled;
  final bool isLoading;
  
  const FooterButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.enabled = true,
    this.isLoading = false,
  });
}
```

### Commenting Guidelines

**Philosophy:** Code should be self-documenting. Use comments strategically, not extensively.

#### When to Comment

✅ **DO comment:**

1. **Complex business logic**
   ```dart
   // Check if wallet is locked due to failed PIN attempts
   // Returns the remaining lockout duration if locked
   static Future<Duration?> getRemainingLockoutDuration() async {
     // ...
   }
   ```

2. **Important warnings**
   ```dart
   // WARNING: This resets all wallet data. Cannot be undone.
   Future<void> wipeWallet() async {
     // ...
   }
   ```

3. **TODOs for future work**
   ```dart
   // todo: show an error screen when wallet is present but fails to load
   ```

4. **Non-obvious design decisions**
   ```dart
   // We use secure storage for keys but SharedPreferences for settings
   // because settings don't need encryption and are faster to access
   ```

5. **Section markers in large files**
   ```dart
   // ===== Secure Storage Keys =====
   const String _keyScanSk = "scansk";
   const String _keySpendSk = "spendsk";
   
   // ===== Non-Secure Storage Keys =====
   const String _keyBirthday = "birthday";
   ```

❌ **DON'T comment:**

1. **Obvious code**
   ```dart
   ❌ // Set the text
   text = "Hello";
   
   ❌ // Get the wallet balance
   final balance = walletState.balance;
   ```

2. **Self-explanatory function names**
   ```dart
   ❌ // Displays an error notification
   void displayError(String message) {
     // Function name already describes this
   }
   ```

3. **Repeating the code**
   ```dart
   ❌ // Loop through contacts
   for (var contact in contacts) {
     // Process contact
   }
   ```

#### Doc Comments (///)

Use doc comments sparingly for public APIs:

```dart
✅ /// Creates a new wallet with the given mnemonic and network.
/// 
/// Throws [WalletException] if the mnemonic is invalid.
static Future<void> createWallet({
  required String mnemonic,
  required Network network,
}) async {
  // ...
}
```

**Note:** Dana wallet does NOT extensively use doc comments. Most functions are self-explanatory.

### Null Safety

Dana uses full null safety. Follow these conventions:

```dart
✅ String? optionalValue;  // Can be null
✅ String definiteValue;   // Never null

✅ if (optionalValue != null) {
     print(optionalValue.length);  // Safe
   }

✅ print(optionalValue?.length ?? 0);  // Null-aware operator

✅ print(optionalValue!);  // Force unwrap (only if certain it's not null)

❌ print(optionalValue.length);  // Compile error if nullable
```

### Async/Await

Always use `async`/`await` over raw `Future` callbacks:

```dart
✅ Future<void> loadWallet() async {
  final scanKey = await WalletRepository.instance.getScanSk();
  final wallet = await createWallet(scanKey: scanKey);
  await saveWallet(wallet);
}

❌ Future<void> loadWallet() {
  return WalletRepository.instance.getScanSk().then((scanKey) {
    return createWallet(scanKey: scanKey).then((wallet) {
      return saveWallet(wallet);
    });
  });
}
```

### Error Handling

Use `try-catch` at appropriate boundaries:

```dart
✅ Future<void> fetchExchangeRate() async {
  try {
    final rate = await mempoolApi.getExchangeRate();
    _exchangeRate = rate;
  } catch (e) {
    logger.w("Failed to fetch exchange rate: $e");
    // Don't crash - exchange rate is optional
  }
}

✅ Future<void> broadcastTransaction() async {
  try {
    await mempoolApi.broadcast(tx);
    displayNotification("Transaction sent!");
  } catch (e) {
    displayError("Failed to broadcast: ${e.toString()}");
  }
}
```

---

## Rust Standards

### File & Module Naming

All Rust files use **snake_case**:

```
✅ rust/src/wallet.rs
✅ rust/src/api/backup.rs
✅ rust/src/state/updater.rs

❌ rust/src/Wallet.rs
❌ rust/src/api/Backup.rs
```

### Module Structure

#### Root Module (lib.rs)

```rust
✅ // rust/src/lib.rs
pub mod api;
pub mod logger;
pub mod state;
pub mod stream;
pub mod wallet;

// Re-export for convenience
pub use wallet::Wallet;
```

#### Sub-Module (mod.rs)

```rust
✅ // rust/src/api/mod.rs
// Do not put code in mod.rs, but in separate files

pub mod backup;
pub mod bip39;
pub mod chain;
pub mod history;
pub mod outputs;
pub mod stream;
pub mod validate;
pub mod wallet;

// Re-export important types
pub use wallet::{ApiWalletInfo, ApiRecipient};
```

### Type Naming

#### Structs & Enums: PascalCase

```rust
✅ pub struct Wallet { }
✅ pub struct ApiAmount(pub u64);
✅ pub enum Network { Mainnet, Testnet, Signet, Regtest }

❌ pub struct wallet { }
❌ pub enum network { }
```

#### Functions & Variables: snake_case

```rust
✅ pub fn create_new_wallet() -> anyhow::Result<Wallet> { }
✅ fn calculate_fee_rate(tx_size: usize) -> u64 { }
✅ let scan_key = get_scan_key()?;

❌ pub fn CreateNewWallet() -> anyhow::Result<Wallet> { }
❌ fn CalculateFeeRate(txSize: usize) -> u64 { }
```

#### API Boundary Types: "Api" Prefix

All types exposed to Dart must have the "Api" prefix:

```rust
✅ // API types (exposed to Dart)
pub struct ApiAmount(pub u64);
pub struct ApiScanKey(pub String);
pub struct ApiWalletInfo { ... }
pub enum ApiOutputSpendStatus { ... }

// Internal types (Rust only)
struct Wallet { ... }
struct Transaction { ... }
```

**Rationale:** Clear separation between FFI boundary and internal implementation.

### Error Handling

#### Use anyhow::Result<T>

All fallible functions return `anyhow::Result<T>`:

```rust
✅ use anyhow::{Result, Error};

pub fn create_wallet(mnemonic: String) -> Result<ApiWalletInfo> {
    let seed = parse_mnemonic(&mnemonic)?;  // ? operator for propagation
    let wallet = Wallet::new(seed)?;
    Ok(wallet.into())
}

❌ pub fn create_wallet(mnemonic: String) -> ApiWalletInfo {
    // No error handling
}
```

#### Error Propagation with ?

```rust
✅ pub fn load_wallet() -> Result<Wallet> {
    let scan_key = get_scan_key()?;  // Propagate error
    let spend_key = get_spend_key()?;
    let wallet = Wallet::from_keys(scan_key, spend_key)?;
    Ok(wallet)
}
```

#### Selective .unwrap()

Use `.unwrap()` only when:
- Error is truly impossible
- In test code
- After explicit error checking

```rust
✅ // Safe: we just checked it exists
if lock.is_some() {
    let value = lock.unwrap();
}

✅ // Safe: mutex poison is unrecoverable anyway
let state = STATE.lock().unwrap();

❌ // Dangerous: could panic
let key = get_key().unwrap();
```

#### Custom Error Messages

```rust
✅ use anyhow::Error;

let wallet = load_wallet()
    .map_err(|e| Error::msg(format!("Failed to load wallet: {}", e)))?;
```

### Code Patterns

#### Global State with lazy_static

```rust
✅ use lazy_static::lazy_static;
use std::sync::Mutex;

lazy_static! {
    pub static ref WALLET: Mutex<Option<Wallet>> = Mutex::new(None);
}

// Usage
let mut wallet = WALLET.lock().unwrap();
*wallet = Some(new_wallet);
```

#### Newtype Pattern

```rust
✅ // Wrapper type for semantic clarity
pub struct ApiAmount(pub u64);
pub struct ApiScanKey(pub String);

impl ApiAmount {
    pub fn from_btc(btc: f64) -> Self {
        ApiAmount((btc * 100_000_000.0) as u64)
    }
    
    pub fn to_btc(&self) -> f64 {
        self.0 as f64 / 100_000_000.0
    }
}
```

#### Type Conversions

```rust
✅ // From trait for infallible conversions
impl From<Wallet> for ApiWalletInfo {
    fn from(wallet: Wallet) -> Self {
        ApiWalletInfo {
            receiving_address: wallet.address().to_string(),
            balance: ApiAmount(wallet.balance()),
        }
    }
}

// TryFrom trait for fallible conversions
impl TryFrom<String> for Network {
    type Error = anyhow::Error;
    
    fn try_from(s: String) -> Result<Self, Self::Error> {
        match s.as_str() {
            "mainnet" => Ok(Network::Mainnet),
            "testnet" => Ok(Network::Testnet),
            _ => Err(Error::msg("Invalid network")),
        }
    }
}
```

#### Async Functions

```rust
✅ pub async fn broadcast_transaction(tx: String) -> Result<String> {
    let client = reqwest::Client::new();
    let response = client.post("https://api.example.com/tx")
        .body(tx)
        .send()
        .await?;
    
    let txid = response.text().await?;
    Ok(txid)
}
```

#### StreamSink Pattern (Rust → Dart)

```rust
✅ use flutter_rust_bridge::StreamSink;

lazy_static! {
    pub static ref STATE_STREAM: Mutex<Option<StreamSink<StateUpdate>>> = 
        Mutex::new(None);
}

pub fn stream_state_updates(sink: StreamSink<StateUpdate>) {
    *STATE_STREAM.lock().unwrap() = Some(sink);
}

pub fn send_update(update: StateUpdate) {
    if let Some(sink) = STATE_STREAM.lock().unwrap().as_ref() {
        sink.add(update);
    }
}
```

### Commenting Guidelines (Rust)

Similar to Dart: minimal, strategic comments.

#### When to Comment

✅ **DO comment:**

1. **Complex algorithms**
   ```rust
   // Use BDK coin selection algorithm to minimize fees
   // while ensuring sufficient inputs for the transaction
   let selection = coin_select(&utxos, target_amount)?;
   ```

2. **Important warnings**
   ```rust
   // WARNING: This function should only be used on regtest.
   // Using on mainnet will cause privacy loss!
   pub fn expose_scan_key() -> String {
       // ...
   }
   ```

3. **TODOs**
   ```rust
   // todo: add more loggers for different modules
   ```

4. **Non-obvious match arms**
   ```rust
   match update {
       StateUpdate::Balance(_) => {
           // Continue processing
       }
       _ => {
           // Ignore other update types for now
           return;
       }
   }
   ```

❌ **DON'T comment:**

1. **Obvious code**
   ```rust
   ❌ // Create a new wallet
   let wallet = Wallet::new(seed)?;
   
   ❌ // Return the balance
   return wallet.balance();
   ```

2. **Type information (use types instead)**
   ```rust
   ✅ fn calculate_fee(tx_size: usize, fee_rate: u64) -> u64
   
   ❌ // Calculates fee given tx size (usize) and fee rate (u64), returns u64
      fn calculate_fee(tx_size: usize, fee_rate: u64) -> u64
   ```

---

## Cross-Language Patterns

### FFI Type Conversions

#### Dart → Rust

```dart
// Dart side
final scanKey = ApiScanKey("secret_key_here");
await RustLib.instance.api.saveScanKey(scanKey: scanKey);
```

```rust
// Rust side
pub fn save_scan_key(scan_key: ApiScanKey) -> Result<()> {
    // ApiScanKey is a newtype wrapper
    let key_string = scan_key.0;
    // ... save to storage
    Ok(())
}
```

#### Rust → Dart

```rust
// Rust side
pub fn get_wallet_info() -> Result<ApiWalletInfo> {
    let wallet = WALLET.lock().unwrap();
    let wallet = wallet.as_ref().ok_or(Error::msg("No wallet"))?;
    
    Ok(ApiWalletInfo {
        receiving_address: wallet.address(),
        balance: ApiAmount(wallet.balance()),
    })
}
```

```dart
// Dart side
final info = await RustLib.instance.api.getWalletInfo();
String address = info.receivingAddress;
int balanceSats = info.balance.field0;
```

### Extension Methods for Generated Types

Dart can extend generated Rust types:

```dart
// lib/extensions/api_amount.dart
extension ApiAmountExtension on ApiAmount {
  String displayInBtc() {
    return (this.field0 / 100000000).toStringAsFixed(8);
  }
  
  String displayInSats() {
    return this.field0.toString();
  }
}

// Usage
final amount = ApiAmount(100000);
print(amount.displayInBtc());  // "0.00100000"
```

---

## Documentation Standards

### README Updates

Update `README.md` when:
- Adding new build steps
- Changing dependencies
- Adding new features (user-facing)
- Changing deployment process

### Code Documentation

**For Functions:**
```dart
// Good: self-documenting name
Future<void> validateAndSaveDanaAddress(String address) async { }

// Only add doc comment if truly needed
/// Validates a Dana address against the name server
/// and saves it to secure storage if valid.
///
/// Throws [InvalidAddressException] if validation fails.
Future<void> validateAndSaveDanaAddress(String address) async { }
```

**For Complex Classes:**
```dart
/// Manages the state of blockchain synchronization.
///
/// Coordinates periodic block fetching, handles sync errors,
/// and notifies listeners of sync progress.
class ChainState extends ChangeNotifier {
  // ...
}
```

---

## Quick Reference

### Dart Checklist

- [ ] File names in `snake_case` with appropriate suffix
- [ ] Classes in `PascalCase`
- [ ] Functions/variables in `camelCase`
- [ ] Private members start with `_`
- [ ] Imports organized in 3 sections
- [ ] Use `const` constructors where possible
- [ ] Prefer `StatelessWidget` over `StatefulWidget`
- [ ] Use `async`/`await` consistently
- [ ] Handle errors with `try-catch` at boundaries
- [ ] Comments only where needed (strategic, not extensive)

### Rust Checklist

- [ ] File names in `snake_case`
- [ ] Structs/enums in `PascalCase`
- [ ] Functions/variables in `snake_case`
- [ ] All FFI types have `Api` prefix
- [ ] Use `anyhow::Result<T>` for fallible functions
- [ ] Use `?` operator for error propagation
- [ ] Minimize `.unwrap()` usage
- [ ] Use `lazy_static!` for global state
- [ ] Implement `From`/`TryFrom` for type conversions
- [ ] Comments only where needed (strategic, not extensive)

### Common Patterns at a Glance

| Pattern | Dart | Rust |
|---------|------|------|
| Singleton | `ClassName._(); static final instance = ...` | `lazy_static! { static ref ... }` |
| Error Handling | `try-catch` | `Result<T>` with `?` |
| Async | `async`/`await` | `async`/`await` |
| Null Safety | `String?`, `?.`, `??`, `!` | `Option<T>`, `?`, `.unwrap_or()` |
| Immutability | `const`, `final` | `let` (immutable by default) |
| Private | `_memberName` | `mod` visibility, not `pub` |

---

## Related Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Project structure and architecture
- [GIT_WORKFLOW.md](./GIT_WORKFLOW.md) - Commit conventions and workflow
- [DEVELOPMENT.md](./DEVELOPMENT.md) - Build system and setup

---

**Last Updated:** February 2026  
**Dana Version:** 0.7.1-rc2  
**Maintainers:** Dana Wallet Team
