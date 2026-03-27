import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:danawallet/data/models/dana_backup.dart';
import 'package:danawallet/exceptions.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/services/crypto.dart';
import 'package:file_picker/file_picker.dart';

class BackupService {
  /// Create a [DanaBackup] from all storage layers.
  static Future<DanaBackup> _createBackup() async {
    final walletRepository = WalletRepository.instance;
    final settingsRepository = SettingsRepository.instance;

    final wallet = await walletRepository.createWalletBackup();
    final transactionData =
        await walletRepository.createTransactionDataBackup();
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

  /// Encrypt and save backup to a user-selected file.
  static Future<bool> backupToFile(String password) async {
    final backup = await _createBackup();
    final plaintext = utf8.encode(backup.encode());
    final encrypted =
        await BackupCrypto.encrypt(Uint8List.fromList(plaintext), password);

    final outputFilePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select an output file:',
        fileName: 'danawallet.bak',
        bytes: encrypted);

    if (Platform.isLinux && outputFilePath != null) {
      final file = File(outputFilePath);
      await file.writeAsBytes(encrypted);
      return true;
    }

    return outputFilePath != null;
  }

  /// Pick a backup file and return the raw encrypted bytes.
  static Future<Uint8List?> getBackupFromFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      return await file.readAsBytes();
    } else {
      return null;
    }
  }

  /// Decrypt and restore from encrypted backup bytes.
  static Future<void> restoreFromFile(
      Uint8List encryptedBackup, String password) async {
    final plaintext = await BackupCrypto.decrypt(encryptedBackup, password);
    final backup = DanaBackup.decode(utf8.decode(plaintext));
    await _restoreBackup(backup);
  }
}
