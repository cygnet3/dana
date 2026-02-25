import 'dart:convert';
import 'dart:io';

import 'package:danawallet/data/models/dana_backup.dart';
import 'package:danawallet/exceptions.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:file_picker/file_picker.dart';

class BackupService {
  /// Create a [DanaBackup] from all storage layers.
  static Future<DanaBackup> _createBackup() async {
    final walletRepository = WalletRepository.instance;
    final settingsRepository = SettingsRepository.instance;

    final wallet = await walletRepository.createWalletBackup();
    final transactionData = await walletRepository.createTransactionDataBackup();
    final settings = await settingsRepository.createSettingsBackup();

    return DanaBackup(
      wallet: wallet,
      data: transactionData,
      settings: settings,
    );
  }

  /// Restore a [DanaBackup] into all storage layers.
  static Future<void> _restoreBackup(DanaBackup backup) async {
    final walletRepository = WalletRepository.instance;
    final settingsRepository = SettingsRepository.instance;

    final expectedNetwork = getNetworkForFlavor;

    // dev flavor allows any network
    if (!isDevEnv && backup.wallet.network != expectedNetwork.name) {
      throw InvalidNetworkException();
    }

    await walletRepository.restoreWallet(backup.wallet);
    await walletRepository.restoreTransactionData(backup.data);
    await settingsRepository.restoreSettingsBackup(backup.settings);
  }

  // TODO: Phase 2 — replace with proper encryption (PBKDF2 + AES-256-GCM)
  static Future<bool> backupToFile(String password) async {
    final backup = await _createBackup();
    final plaintext = backup.encode();

    // Temporary: write plaintext JSON (encryption will be added in Phase 2)
    final bytes = utf8.encode(plaintext);

    final outputFilePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select an output file:',
        fileName: 'danawallet',
        bytes: bytes);

    if (Platform.isLinux && outputFilePath != null) {
      final file = File(outputFilePath);
      await file.writeAsBytes(bytes);
      return true;
    }

    return outputFilePath != null;
  }

  // TODO: Phase 2 — replace with proper decryption
  static Future<String?> getBackupFromFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      return utf8.decode(await file.readAsBytes());
    } else {
      return null;
    }
  }

  // TODO: Phase 2 — replace with proper decryption
  static Future<void> restoreFromFile(
      String encodedBackup, String password) async {
    final backup = DanaBackup.decode(encodedBackup);
    await _restoreBackup(backup);
  }
}
