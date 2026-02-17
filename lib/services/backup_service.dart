import 'dart:convert';
import 'dart:io';

import 'package:danawallet/exceptions.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/backup.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:file_picker/file_picker.dart';

class BackupService {
  // Since we're just using a password to derive a 32-bit key,
  // we don't really have the randomness of a proper 32-bit random
  // number. So, unless we can guarantee that the source is decently random,
  // this encryption step is little more than symbolic.
  //
  // I think for 'real' backups, we don't let the user pick a password.
  // Instead, we randomly generate a passphrase, like what password managers do.
  // E.g.: "clutter-growl-devalue"
  //
  // Although, if we do that, we have to tell the user that they have to
  // store this backup file ALONG WITH the passphrase.
  //
  // That might be too big of a hurdle to make UX wise.
  static Future<bool> backupToFile(String password) async {
    WalletRepository walletRepository = WalletRepository.instance;
    SettingsRepository settingsRepository = SettingsRepository.instance;

    final walletBackup = await walletRepository.createWalletBackup();
    final settingsBackup = await settingsRepository.createSettingsBackup();

    final danaBackup =
        DanaBackup(wallet: walletBackup, settings: settingsBackup);

    final encrypted = danaBackup.encrypt(password: password);
    final bytes = utf8.encode(encrypted.encode());

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

  static Future<EncryptedDanaBackup?> getEncryptedBackupFromFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      String encodedBackup = utf8.decode(await file.readAsBytes());
      return EncryptedDanaBackup.decode(encoded: encodedBackup);
    } else {
      return null;
    }
  }

  static Future<void> restoreFromEncryptedBackup(
      EncryptedDanaBackup encryptedBackup, String password) async {
    WalletRepository walletRepository = WalletRepository.instance;
    SettingsRepository settingsRepository = SettingsRepository.instance;
    final backup = encryptedBackup.decrypt(password: password);

    final expectedNetwork = getNetworkForFlavor;

    // dev flavor allows any network
    if (isDevEnv || backup.wallet.network == expectedNetwork) {
      await walletRepository.restoreWalletBackup(backup.wallet);
      await settingsRepository.restoreSettingsBackup(backup.settings);
    } else {
      throw InvalidNetworkException();
    }
  }
}
