# Dana Wallet Development Guide

> Complete guide to setting up, building, and developing Dana wallet.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Build System](#build-system)
- [Running the App](#running-the-app)
- [Development Workflow](#development-workflow)
- [Code Generation](#code-generation)
- [Testing](#testing)
- [Debugging](#debugging)
- [Troubleshooting](#troubleshooting)
- [Quick Reference](#quick-reference)

---

## Prerequisites

### Required Tools

#### Flutter & Dart
- **Flutter SDK**: 3.5.2 or higher
- **Dart SDK**: Included with Flutter
- **FVM (Optional but Recommended)**: Flutter Version Management

```bash
# Install FVM (optional)
dart pub global activate fvm

# Or use Flutter directly
flutter --version
```

#### Rust
- **Rust**: Latest stable version
- **cargo**: Included with Rust
- **cargo-ndk**: For Android builds

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install cargo-ndk
cargo install cargo-ndk

# Add Android targets
rustup target add \
    aarch64-linux-android \
    armv7-linux-androideabi \
    x86_64-linux-android \
    i686-linux-android
```

#### Build Tools
- **just**: Command runner (alternative to Make)

```bash
# macOS
brew install just

# Linux
cargo install just

# Or use package manager
```

#### Platform-Specific

**For Android:**
- Android SDK
- Android NDK
- Android Studio (recommended) or command-line tools

**For iOS:**
- Xcode (macOS only)
- CocoaPods

**For Linux Desktop:**
- Standard Linux development tools (gcc, cmake, etc.)

**For macOS Desktop:**
- Xcode command-line tools

---

## Initial Setup

### 1. Clone the Repository

```bash
git clone https://github.com/cygnet3/danawallet.git
cd danawallet
```

### 2. Install Flutter Dependencies

```bash
# If using fvm
fvm flutter pub get

# If using flutter directly
flutter pub get
```

### 3. Verify Installation

```bash
# Check Flutter setup
fvm flutter doctor

# Check available devices
fvm flutter devices
```

You should see output indicating:
- ✅ Flutter SDK installed
- ✅ Dart SDK installed
- ✅ At least one connected device or emulator

---

## Build System

Dana uses **justfile** for build automation (similar to Makefiles).

### Justfile Commands

View available commands:

```bash
just --list
```

### Root Justfile (`./justfile`)

Located at project root, handles Flutter-level tasks:

| Command | Description |
|---------|-------------|
| `just run` | Run app with local flavor (default) |
| `just run-release` | Run app in release mode with local flavor |
| `just clean-bin` | Clean Rust binaries |
| `just gen` | Generate Rust bridge code |
| `just build-emulator` | Build Rust for Android emulator |
| `just build-android` | Build Rust for Android devices |
| `just gen-rust` | Generate + build Android (convenience) |

### Rust Justfile (`./rust/justfile`)

Located in `rust/` directory, handles Rust-level tasks:

```bash
cd rust
just --list
```

Common commands:
- `just gen` - Generate flutter_rust_bridge bindings
- `just build-android` - Build for all Android architectures
- `just build-emulator` - Build for Android emulator only
- `just clean-bin` - Clean build artifacts

---

## Running the App

### Quick Start (Linux/macOS Desktop)

Simplest way to run Dana:

```bash
# From project root
fvm flutter run

# Or with just
just run
```

This runs the **local flavor** which is configured for development.

### Running with Different Flavors

Dana has multiple build flavors for different networks:

| Flavor | Network | Use Case |
|--------|---------|----------|
| `local` | Regtest | Local development (default) |
| `dev` | Regtest | Development with experimental features |
| `signet` | Signet | Testing with signet testnet |
| `live` | Mainnet | Production (real Bitcoin) |

**Run specific flavor:**

```bash
# Local flavor (development)
fvm flutter run --flavor local --target lib/main_local.dart

# Live flavor (production)
fvm flutter run --flavor live --target lib/main.dart
```

**Using justfile:**

```bash
# Development mode (debug)
just run

# Release mode (optimized)
just run-release
```

### Running on Android

#### First Time Setup

Generate Android binaries:

```bash
# Build Rust binaries for Android
just build-android

# Or step by step
cd rust
just build-android
cd ..
```

This creates binaries for all Android architectures:
- `aarch64-linux-android` (ARM64)
- `armv7-linux-androideabi` (ARM)
- `x86_64-linux-android` (x86_64)
- `i686-linux-android` (x86)

#### Connect Device

```bash
# Enable USB debugging on your Android device
# Connect via USB

# Verify device is connected
fvm flutter devices

# Should show something like:
# SM G960F (mobile) • XXXXXXX • android-arm64 • Android 10
```

#### Run on Device

```bash
# Debug build
fvm flutter run --flavor local --target lib/main_local.dart

# Release build (optimized)
fvm flutter run --release --flavor local --target lib/main_local.dart
```

### Running on iOS

```bash
# Open iOS simulator
open -a Simulator

# Run app
fvm flutter run --flavor local --target lib/main_local.dart
```

### Running on Emulator/Simulator

```bash
# List available emulators
fvm flutter emulators

# Launch specific emulator
fvm flutter emulators --launch <emulator_id>

# Run app on emulator
fvm flutter run
```

---

## Development Workflow

### Typical Development Cycle

1. **Make code changes** in `lib/` (Dart) or `rust/src/` (Rust)

2. **Hot reload** (if running):
   - Press `r` in terminal
   - Or use IDE hot reload button
   - Changes appear instantly (Dart only)

3. **Hot restart** (if Rust changes or major Dart changes):
   - Press `R` in terminal
   - Or use IDE hot restart button
   - Restarts app from scratch

4. **Full rebuild** (if generated code or build config changed):
   - Stop app
   - Run `fvm flutter run` again

### When to Regenerate Bindings

You need to regenerate Flutter Rust Bridge code when:
- Adding/modifying Rust API functions
- Changing Rust struct definitions exposed to Dart
- Adding new Rust modules with FFI

```bash
# Regenerate bindings
just gen

# For Android, also rebuild binaries
just gen-rust
```

### Linting and Formatting

#### Dart

```bash
# Run analyzer
fvm flutter analyze

# Format code
fvm flutter format lib/

# Format specific file
fvm flutter format lib/screens/wallet/wallet_screen.dart
```

**Lint Configuration:** `analysis_options.yaml`

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - rust_builder
    - lib/generated/**/*
```

#### Rust

```bash
cd rust

# Check for issues
cargo clippy

# Format code
cargo fmt

# Format and check
cargo fmt && cargo clippy
```

### File Watching

For continuous linting during development:

```bash
# Terminal 1: Run app
just run

# Terminal 2: Watch for lint errors
fvm flutter analyze --watch
```

---

## Code Generation

### Flutter Rust Bridge

Dana uses `flutter_rust_bridge` to generate FFI bindings between Dart and Rust.

#### When to Regenerate

Regenerate when you modify:
- `rust/src/api/**/*.rs` - API boundary files
- Any Rust types/functions marked with `#[flutter_rust_bridge::frb]`

#### Generation Process

```bash
# Step 1: Generate bindings (creates Dart files)
cd rust
just gen

# Step 2: Rebuild Rust binaries for your platform
# For desktop (Linux/macOS)
cargo build

# For Android
just build-android

# For Android emulator specifically
just build-emulator
```

**Output locations:**
- Dart code: `lib/generated/rust/**/*.dart`
- Rust code: `rust/src/frb_generated.rs` (and related)

#### Manual Generation (if needed)

```bash
# Install codegen tool
cargo install flutter_rust_bridge_codegen

# Generate from rust directory
cd rust
flutter_rust_bridge_codegen generate
```

### Freezed (Data Classes)

If you add/modify data classes using `freezed`:

```bash
# Generate freezed code
fvm flutter pub run build_runner build

# Watch for changes
fvm flutter pub run build_runner watch

# Clean and regenerate
fvm flutter pub run build_runner build --delete-conflicting-outputs
```

**Note:** Dana uses `freezed` sparingly. Check `pubspec.yaml` `dev_dependencies` for current status.

---

## Testing

### Current State

Dana wallet is in **experimental phase** and does not currently have comprehensive test coverage.

### Future Testing Strategy

When tests are added, they will likely follow this structure:

```
test/
├── unit/              # Unit tests
├── widget/            # Widget tests
└── integration/       # Integration tests
```

### Manual Testing Checklist

For now, manual testing is required:

#### New Wallet Flow
- [ ] Create new wallet
- [ ] View and verify seed phrase
- [ ] Set PIN code
- [ ] Wallet loads successfully

#### Restore Wallet Flow
- [ ] Enter valid seed phrase
- [ ] Set birthday (if applicable)
- [ ] Set PIN code
- [ ] Wallet restores correctly

#### Receive Flow
- [ ] View receiving address
- [ ] Share via QR code
- [ ] Copy address to clipboard

#### Send Flow
- [ ] Enter amount
- [ ] Select recipient
- [ ] Choose fee
- [ ] Verify transaction details
- [ ] Broadcast transaction

#### Settings
- [ ] Change network settings
- [ ] View wallet info
- [ ] Backup wallet

### Testing Different Networks

Use different flavors to test on different networks:

```bash
# Signet (test network)
fvm flutter run --flavor signet

# Mainnet (use with caution!)
fvm flutter run --flavor live
```

**Get test coins for Signet:**
- Visit: https://silentpayments.dev/faucet/signet
- Enter your Dana address
- Wait for confirmation

---

## Debugging

### Flutter DevTools

Launch DevTools for advanced debugging:

```bash
# While app is running
fvm flutter pub global activate devtools
fvm flutter pub global run devtools
```

Features:
- Widget inspector
- Performance profiling
- Memory profiling
- Network inspector
- Logging

### Logging

Dana uses the `logger` package for structured logging.

#### Dart Logging

```dart
import 'package:logger/logger.dart';

final logger = Logger();

// Different log levels
logger.d("Debug message");
logger.i("Info message");
logger.w("Warning message");
logger.e("Error message");
```

**View logs:**
- In terminal where `flutter run` is active
- In IDE debug console

#### Rust Logging

```rust
// Rust logs are forwarded to Flutter logger
// Use standard Rust logging
log::debug!("Debug message");
log::info!("Info message");
log::warn!("Warning message");
log::error!("Error message");
```

### Debugging Tips

#### Hot Reload Not Working

```bash
# Stop app and restart
# Press Ctrl+C

# Clean build
fvm flutter clean
fvm flutter pub get

# Restart
just run
```

#### Rust Changes Not Reflected

```bash
# Regenerate bindings and rebuild
just gen-rust

# Or manually
cd rust
just gen
just build-android  # or cargo build for desktop
cd ..

# Then restart app
just run
```

#### Performance Issues

```bash
# Run in release mode
just run-release

# Or
fvm flutter run --release
```

#### Check for Issues

```bash
# Dart analysis
fvm flutter analyze

# Rust checks
cd rust
cargo clippy
cargo check
```

---

## Troubleshooting

### Common Issues

#### Issue: "Target of URI doesn't exist"

**Cause:** Missing imports or file paths changed

**Solution:**
1. Run `fvm flutter pub get`
2. Check import paths in error files
3. Verify files exist at specified locations

#### Issue: "cargo-ndk not found"

**Cause:** cargo-ndk not installed

**Solution:**
```bash
cargo install cargo-ndk
```

#### Issue: "No Android NDK found"

**Cause:** Android NDK not installed or not in PATH

**Solution:**
1. Open Android Studio
2. Go to SDK Manager → SDK Tools
3. Install NDK
4. Update PATH or set ANDROID_NDK_HOME

#### Issue: "flutter_rust_bridge_codegen not found"

**Cause:** Codegen tool not installed

**Solution:**
```bash
cargo install flutter_rust_bridge_codegen
```

#### Issue: Build fails with "undefined symbols"

**Cause:** Rust binaries not built for target platform

**Solution:**
```bash
# For Android
just build-android

# For desktop
cd rust
cargo build
cd ..
```

#### Issue: "Could not find fvm"

**Cause:** FVM not installed or not in PATH

**Solution:**
```bash
# Install FVM
dart pub global activate fvm

# Or use flutter directly instead
flutter run  # instead of fvm flutter run
```

#### Issue: App crashes immediately on startup

**Cause:** Multiple possible causes

**Solution:**
1. Check logs: `fvm flutter logs`
2. Clean and rebuild:
   ```bash
   fvm flutter clean
   just clean-bin
   fvm flutter pub get
   just build-android  # if Android
   just run
   ```
3. Verify network settings match flavor

### Getting Help

If you encounter issues:

1. **Check logs:**
   ```bash
   fvm flutter logs
   ```

2. **Run flutter doctor:**
   ```bash
   fvm flutter doctor -v
   ```

3. **Check GitHub issues:**
   - https://github.com/cygnet3/danawallet/issues

4. **Ask the team:**
   - File a new GitHub issue with:
     - Error message
     - Steps to reproduce
     - Platform (Android/iOS/Linux/etc.)
     - Flutter/Rust versions

---

## Quick Reference

### Essential Commands

```bash
# Run app (development)
just run

# Run app (release mode)
just run-release

# Generate Rust bindings
just gen

# Build for Android
just build-android

# Regenerate everything
just gen-rust

# Clean builds
fvm flutter clean
just clean-bin

# Check for issues
fvm flutter analyze
fvm flutter doctor
```

### File Locations

| What | Where |
|------|-------|
| Main Dart code | `lib/` |
| Rust code | `rust/src/` |
| Generated Dart code | `lib/generated/rust/` |
| Generated Rust code | `rust/src/frb_generated.*` |
| Build scripts | `justfile`, `rust/justfile` |
| Flutter config | `pubspec.yaml` |
| Rust config | `rust/Cargo.toml` |
| Lint config | `analysis_options.yaml` |

### Development Checklist

Before committing:
- [ ] Code formatted (`fvm flutter format .`)
- [ ] No lint errors (`fvm flutter analyze`)
- [ ] App runs successfully
- [ ] Manual testing completed
- [ ] Commit message follows conventions
- [ ] No debug code left behind

Before pushing:
- [ ] All commits are meaningful
- [ ] Commit messages follow git workflow
- [ ] No sensitive data in commits
- [ ] Branch is up to date with main

---

## Related Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Project architecture overview
- [CODING_STANDARDS.md](./CODING_STANDARDS.md) - Code style and patterns
- [GIT_WORKFLOW.md](./GIT_WORKFLOW.md) - Git conventions and workflow

---

## Additional Resources

### Flutter
- [Flutter Documentation](https://docs.flutter.dev/)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [Flutter Packages](https://pub.dev/)

### Rust
- [Rust Book](https://doc.rust-lang.org/book/)
- [Rust by Example](https://doc.rust-lang.org/rust-by-example/)
- [Flutter Rust Bridge](https://cjycode.com/flutter_rust_bridge/)

### Bitcoin
- [Silent Payments](https://github.com/bitcoin/bips/blob/master/bip-0352.mediawiki)
- [BIP353](https://github.com/bitcoin/bips/blob/master/bip-0353.mediawiki)

---

**Last Updated:** February 2026  
**Dana Version:** 0.7.1-rc2  
**Maintainers:** Dana Wallet Team
