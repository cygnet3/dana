# Dana Wallet Architecture Guide

> A comprehensive guide to understanding the Dana wallet's architecture, project structure, and design patterns.

## Table of Contents

- [Overview](#overview)
- [Technology Stack](#technology-stack)
- [Project Structure](#project-structure)
- [Layered Architecture](#layered-architecture)
- [Module Organization](#module-organization)
- [State Management](#state-management)
- [Rust Integration](#rust-integration)
- [Data Flow](#data-flow)
- [Key Components](#key-components)

---

## Overview

Dana wallet is a Flutter-based mobile application for Bitcoin silent payments. It uses a hybrid architecture combining:

- **Flutter (Dart)** for the UI and application layer
- **Rust** for cryptographic operations, wallet logic, and blockchain interactions
- **Flutter Rust Bridge** for seamless FFI (Foreign Function Interface) communication

**Project Stats:**
- 109 Dart files
- ~30 Rust source files
- 699+ commits
- Version: 0.7.1-rc2

---

## Technology Stack

### Frontend Layer
- **Flutter** (SDK 3.5.2+)
- **Provider** for state management
- **bitcoin_ui** for Bitcoin-themed UI components
- **flutter_secure_storage** for sensitive data

### Backend Layer
- **Rust** (latest stable)
- **anyhow** for error handling
- **tokio** for async runtime
- **serde** for serialization
- **flutter_rust_bridge** (2.11.1) for Dart FFI

### Build Tools
- **just** (justfile) for task automation
- **fvm** (Flutter Version Management) support
- **cargo** for Rust builds

### Database & Storage
- **SQLite** (sqflite) for contacts
- **SharedPreferences** for settings
- **FlutterSecureStorage** for keys/sensitive data

---

## Project Structure

```
dana/
├── lib/                          # Flutter/Dart source code (109 files)
│   ├── data/                     # Data layer (16 files)
│   │   ├── enums/               # Network, WarningType, SelectedFee
│   │   └── models/              # Contact, Bip353Address, etc.
│   ├── extensions/              # Dart extensions (ApiAmount, etc.)
│   ├── generated/               # Auto-generated Rust FFI bridge code (18 files)
│   │   └── rust/
│   │       └── api/             # Generated Dart API wrappers
│   ├── repositories/            # Data persistence layer (7 files)
│   │   ├── contacts_repository.dart
│   │   ├── database_helper.dart
│   │   ├── mempool_api_repository.dart
│   │   ├── name_server_repository.dart
│   │   ├── pin_code_repository.dart
│   │   ├── settings_repository.dart
│   │   └── wallet_repository.dart
│   ├── screens/                 # UI screens (31 files)
│   │   ├── home/
│   │   │   ├── contacts/        # Contact management
│   │   │   └── wallet/          # Wallet screens
│   │   │       ├── receive/     # Receive flow
│   │   │       └── spend/       # Spend/send flow
│   │   ├── onboarding/          # Onboarding flow
│   │   │   └── recovery/
│   │   ├── pin/                 # PIN setup/verification
│   │   ├── recovery/            # Seed phrase recovery
│   │   └── settings/            # Settings screens
│   ├── services/                # Business logic layer (8 files)
│   ├── states/                  # State management (6 files)
│   │   ├── chain_state.dart
│   │   ├── contacts_state.dart
│   │   ├── home_state.dart
│   │   ├── scan_progress_notifier.dart
│   │   ├── spend_state.dart
│   │   └── wallet_state.dart
│   ├── widgets/                 # Reusable UI components (17 files)
│   │   ├── alerts/
│   │   ├── buttons/
│   │   │   └── footer/
│   │   ├── icons/
│   │   └── pills/               # Mnemonic word pills
│   ├── constants.dart           # App-wide constants
│   ├── exceptions.dart          # Custom exceptions
│   ├── global_functions.dart    # Global utility functions
│   ├── main.dart                # Main entry point (live/production)
│   └── main_local.dart          # Local development entry point
│
├── rust/                        # Rust backend
│   ├── src/
│   │   ├── api/                 # FFI API boundary
│   │   │   ├── wallet/          # Wallet operations
│   │   │   │   ├── info.rs
│   │   │   │   ├── scan.rs
│   │   │   │   ├── setup.rs
│   │   │   │   └── transaction.rs
│   │   │   ├── backup.rs
│   │   │   ├── bip39.rs
│   │   │   ├── chain.rs
│   │   │   ├── history.rs
│   │   │   ├── outputs.rs
│   │   │   ├── stream.rs
│   │   │   └── validate.rs
│   │   ├── state/               # Global state management
│   │   │   ├── constants.rs
│   │   │   ├── mod.rs
│   │   │   └── updater.rs
│   │   ├── lib.rs               # Root library file
│   │   ├── logger.rs            # Logging service
│   │   ├── stream.rs            # Stream handling
│   │   └── wallet.rs            # Core wallet logic
│   ├── Cargo.toml
│   └── justfile
│
├── android/                     # Android platform files
├── ios/                         # iOS platform files
├── linux/                       # Linux desktop files
├── macos/                       # macOS desktop files
├── windows/                     # Windows desktop files
├── web/                         # Web platform files
├── assets/                      # Images, icons
├── fonts/                       # Custom fonts (Space Grotesk)
├── rust_builder/                # Cargokit integration
├── pubspec.yaml                 # Flutter dependencies
├── analysis_options.yaml        # Dart linter config
└── justfile                     # Build automation
```

---

## Layered Architecture

Dana follows a **3-tier layered architecture** with clear separation of concerns:

### 1. Data Layer (`data/`, `repositories/`)

**Responsibilities:**
- Data models and enums
- Database operations (SQLite)
- Secure storage (keys, sensitive data)
- Settings persistence (SharedPreferences)
- External API communication

**Key Files:**
- `data/models/` - Data classes (Contact, Bip353Address)
- `data/enums/` - Type-safe enumerations (Network, FiatCurrency)
- `repositories/` - Singleton repository classes for data access

**Pattern:** Repository pattern for data abstraction

```dart
// Example: Singleton Repository
class WalletRepository {
  WalletRepository._();  // Private constructor
  static final instance = WalletRepository._();  // Singleton
  
  // Data access methods
  Future<void> saveScanSk(ApiScanKey scanKey) async { ... }
}
```

### 2. Business Logic Layer (`services/`, `states/`)

**Responsibilities:**
- Business rules and validation
- State management (Provider pattern)
- Complex workflows (sending, receiving)
- Background synchronization
- Fee calculation

**Key Files:**
- `services/pin_service.dart` - PIN validation, lockout logic
- `services/bip353_resolver.dart` - Dana address resolution
- `states/wallet_state.dart` - Core wallet state (balance, transactions)
- `states/spend_state.dart` - Send/spend flow state
- `states/chain_state.dart` - Blockchain sync state

**Pattern:** Service layer + ChangeNotifier state providers

```dart
// Example: State Management
class WalletState extends ChangeNotifier {
  WalletState._();  // Private constructor
  
  static Future<WalletState> create() async {
    final instance = WalletState._();
    await instance._initStreams();
    return instance;
  }
  
  // Notify listeners when state changes
  Future<void> updateBalance() async {
    // ... update logic
    notifyListeners();
  }
}
```

### 3. Presentation Layer (`screens/`, `widgets/`)

**Responsibilities:**
- UI rendering
- User interaction handling
- Navigation
- Screen layouts
- Reusable components

**Key Directories:**
- `screens/` - Full-page screens organized by feature
- `widgets/` - Reusable UI components
- `widgets/buttons/footer/` - Specialized button types

**Pattern:** StatelessWidget preferred, screen skeletons for consistent layouts

```dart
// Example: Screen Skeleton Pattern
class OnboardingSkeleton extends StatelessWidget {
  final Widget body;
  final Widget footer;
  
  const OnboardingSkeleton({
    required this.body,
    required this.footer,
  });
  
  @override
  Widget build(BuildContext context) {
    // Consistent layout structure
  }
}
```

---

## Module Organization

### Feature-Based Grouping

Screens are organized by user-facing features, not technical layers:

```
screens/
├── home/
│   ├── contacts/              # Contact management feature
│   │   ├── contacts_screen.dart
│   │   ├── add_contact.dart
│   │   └── edit_contact.dart
│   └── wallet/                # Wallet feature
│       ├── receive/           # Receive money sub-feature
│       └── spend/             # Send money sub-feature
├── onboarding/                # Onboarding feature
├── pin/                       # PIN security feature
└── settings/                  # Settings feature
```

**Benefits:**
- Related functionality co-located
- Easy to navigate by feature
- Clear module boundaries
- Scales well with new features

### Component Hierarchy

**Widgets** are organized by type and purpose:

```
widgets/
├── alerts/                    # Alert dialogs
├── buttons/
│   └── footer/                # Footer button variants
├── icons/                     # Custom icon widgets
└── pills/                     # Mnemonic word pill components
```

---

## State Management

Dana uses the **Provider pattern** for state management.

### Global State Providers

Six main state providers manage application state:

| State Provider | Responsibility | File |
|----------------|----------------|------|
| `WalletState` | Balance, transactions, wallet info | `states/wallet_state.dart` |
| `ChainState` | Blockchain sync, block height | `states/chain_state.dart` |
| `SpendState` | Send/spend transaction flow | `states/spend_state.dart` |
| `ContactsState` | Contact management | `states/contacts_state.dart` |
| `HomeState` | Home screen navigation | `states/home_state.dart` |
| `ScanProgressNotifier` | Blockchain scanning progress | `states/scan_progress_notifier.dart` |

### Provider Setup (main.dart)

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: walletState),
    ChangeNotifierProvider.value(value: chainState),
    ChangeNotifierProvider.value(value: spendState),
    ChangeNotifierProvider.value(value: contactsState),
    ChangeNotifierProvider.value(value: homeState),
    ChangeNotifierProvider.value(value: scanNotifier),
  ],
  child: SilentPaymentApp(landingPage: landingPage),
)
```

### State Creation Pattern

States use **async factory constructors** for initialization:

```dart
// Create state with async initialization
final walletState = await WalletState.create();
final chainState = await ChainState.create();
```

### Consuming State in Widgets

```dart
// Watch for changes
final walletState = context.watch<WalletState>();

// Read once (no rebuild)
final walletState = context.read<WalletState>();
```

---

## Rust Integration

Dana uses **Flutter Rust Bridge** for seamless Dart-Rust communication.

### FFI Architecture

```
┌─────────────────────────────────────────────────┐
│           Dart/Flutter Layer                    │
│  (UI, State Management, Application Logic)      │
└─────────────────┬───────────────────────────────┘
                  │
                  │ Flutter Rust Bridge (FFI)
                  │
┌─────────────────▼───────────────────────────────┐
│              API Boundary                       │
│  (Type conversions, Api* structs)               │
│  lib/generated/rust/   ←→   rust/src/api/      │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│            Rust Core Layer                      │
│  (Crypto, Wallet Logic, Blockchain)             │
│  rust/src/wallet.rs, rust/src/state/           │
└─────────────────────────────────────────────────┘
```

### API Boundary Pattern

All Rust types exposed to Dart have an "Api" prefix:

```rust
// Rust API types (in rust/src/api/)
pub struct ApiAmount(pub u64);
pub struct ApiScanKey(pub String);
pub struct ApiWalletInfo { ... }

// Internal Rust types (in rust/src/)
struct Wallet { ... }
```

### Type Conversion Flow

```dart
// Dart → Rust
ApiScanKey scanKey = ApiScanKey("...");
await RustLib.instance.api.saveScanKey(scanKey: scanKey);

// Rust → Dart
ApiWalletInfo info = await RustLib.instance.api.getWalletInfo();
String address = info.receivingAddress;
```

### Extension Pattern for Generated Types

```dart
// lib/extensions/api_amount.dart
extension ApiAmountExtension on ApiAmount {
  String displayInBtc() {
    return (this.field0 / 100000000).toStringAsFixed(8);
  }
}
```

### Async Communication via Streams

Rust can send updates to Dart via StreamSinks:

```rust
// Rust side
pub static STREAM_SINK: Mutex<Option<StreamSink<StateUpdate>>> = Mutex::new(None);

pub fn send_update(update: StateUpdate) {
    if let Some(sink) = STREAM_SINK.lock().unwrap().as_ref() {
        sink.add(update);
    }
}

// Dart side
RustLib.instance.api.streamStateUpdates().listen((update) {
  // Handle update
});
```

---

## Data Flow

### Typical User Action Flow

```
User Action (UI)
      ↓
Screen Widget
      ↓
State Provider (ChangeNotifier)
      ↓
Repository (data layer)
      ↓
Rust FFI Call (if needed)
      ↓
Rust Backend Processing
      ↓
Return Result
      ↓
Update State
      ↓
notifyListeners()
      ↓
UI Rebuilds
```

### Example: Sending Bitcoin

1. **User enters amount** → `screens/home/wallet/spend/amount_selection_screen.dart`
2. **User selects recipient** → `screens/home/wallet/spend/choose_recipient.dart`
3. **State updated** → `SpendState.setRecipient()`
4. **Create transaction** → `SpendState.createUnsignedTx()` → Rust FFI
5. **Rust processes** → `rust/src/api/wallet/transaction.rs`
6. **User confirms** → `screens/home/wallet/spend/ready_to_send.dart`
7. **Sign & broadcast** → `SpendState.signAndBroadcastTx()` → Rust FFI
8. **Update wallet** → `WalletState.notifyListeners()`
9. **Navigate to success** → `screens/home/wallet/spend/transaction_sent.dart`

---

## Key Components

### Core Repositories

| Repository | Purpose | Storage |
|------------|---------|---------|
| `WalletRepository` | Wallet keys, scan data | FlutterSecureStorage |
| `SettingsRepository` | User preferences | SharedPreferences |
| `ContactsRepository` | Contact list | SQLite database |
| `PinCodeRepository` | PIN hash, lockout state | FlutterSecureStorage |
| `NameServerRepository` | Dana address lookups | HTTP API |
| `MempoolApiRepository` | Fee rates, broadcasting | HTTP API |

### Core Services

| Service | Purpose |
|---------|---------|
| `PinService` | PIN validation, lockout enforcement |
| `Bip353Resolver` | Resolve Dana addresses to payment codes |

### Global Functions

`lib/global_functions.dart` contains cross-cutting utilities:

- `displayNotification()` - Show snackbars
- `displayDialog()` - Show dialogs
- `displayError()` - Handle errors consistently
- `globalNavigatorKey` - Navigate from anywhere

### Constants

`lib/constants.dart` defines app-wide constants:

- Network endpoints (mainnet, testnet, signet, regtest)
- Default values (dust limit, birthday heights)
- Colors (danaBlue)
- Example data for onboarding

---

## Architecture Principles

### 1. Separation of Concerns
- Clear boundaries between data, business logic, and presentation
- Each layer has distinct responsibilities
- No UI logic in repositories, no data access in widgets

### 2. Dependency Injection
- Repositories use singleton pattern
- States created via factory constructors
- Provider pattern for dependency management

### 3. Immutability Where Possible
- Const constructors for widgets
- Freezed for immutable data classes (when used)
- Value types over reference types

### 4. Type Safety
- Strong typing in both Dart and Rust
- Enums for state representation
- Api* types at FFI boundary

### 5. Error Handling
- Result types in Rust (`anyhow::Result<T>`)
- Try-catch in Dart at appropriate boundaries
- User-friendly error messages via `displayError()`

### 6. Async by Default
- Async/await consistently used
- No blocking operations on main thread
- Background sync via periodic tasks

### 7. Security First
- Sensitive data in FlutterSecureStorage
- PIN protection with lockout mechanism
- Keys never logged or exposed

---

## Related Documentation

- [CODING_STANDARDS.md](./CODING_STANDARDS.md) - Coding conventions and patterns
- [GIT_WORKFLOW.md](./GIT_WORKFLOW.md) - Commit message format and workflow
- [DEVELOPMENT.md](./DEVELOPMENT.md) - Build system and development setup

---

**Last Updated:** February 2026  
**Dana Version:** 0.7.1-rc2  
**Maintainers:** Dana Wallet Team
