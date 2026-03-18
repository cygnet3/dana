import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/recovery/view_mnemonic_screen.dart';
import 'package:danawallet/screens/settings/wallet/confirm_reset_wallet.dart';
import 'package:danawallet/screens/settings/wallet/confirm_wallet_deletion.dart';
import 'package:danawallet/screens/settings/widgets/settings_list_tile.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/services/backup_service.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class WalletSettingsScreen extends StatelessWidget {
  const WalletSettingsScreen({super.key});

  List<_WalletSettingsItem> _buildItems(BuildContext context) {
    return [
      _WalletSettingsItem(
        icon: Icons.key_outlined,
        title: 'Show seed phrase',
        subtitle: 'View your recovery phrase',
        onTap: () => _onShowMnemonic(context),
      ),
      if (isDevEnv)
        _WalletSettingsItem(
          icon: Icons.backup_outlined,
          title: 'File backup wallet',
          subtitle: 'Export encrypted wallet backup',
          onTap: () => _onBackupWalletButtonPressed(),
        ),
      _WalletSettingsItem(
        icon: Icons.restore,
        title: 'Reset wallet data',
        subtitle: 'Reset wallet data to its birthday',
        onTap: () => _onResetToBirthdayButtonPressed(context),
        isDestructive: true,
      ),
      _WalletSettingsItem(
        icon: Icons.delete_outline,
        title: 'Wipe wallet',
        subtitle: 'Delete wallet and all data',
        onTap: () => _onWipeWalletButtonPressed(context),
        isDestructive: true,
      ),
    ];
  }

  Future<void> _onBackupWalletButtonPressed() async {
    final controller = TextEditingController();

    final password = await showInputAlertDialog(controller, TextInputType.text,
        'Set backup password', 'set password for backup file',
        showReset: false);

    if (password is String) {
      try {
        await BackupService.backupToFile(password);
      } catch (e) {
        displayNotification("backup failed");
      }
    }
  }

  void _onResetToBirthdayButtonPressed(BuildContext context) {
    goToScreen(context, const ConfirmWalletResetScreen());
  }

  void _onWipeWalletButtonPressed(BuildContext context) {
    goToScreen(context, const ConfirmWalletDeletionScreen());
  }

  void _onShowMnemonic(BuildContext context) async {
    final wallet = Provider.of<WalletState>(context, listen: false);
    final mnemonic = await wallet.getSeedPhraseFromSecureStorage();

    if (context.mounted) {
      if (mnemonic != null) {
        goToScreen(context,
            ViewMnemonicScreen(mnemonic: mnemonic, birthday: wallet.birthday));
      } else {
        showAlertDialog("Seed phrase unknown",
            "Seed phrase unknown! Did you import from keys?");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(context);

    return ScreenSkeleton(
      showBackButton: true,
      title: 'Wallet settings',
      body: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          color: Bitcoin.neutral3,
          indent: 56,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return SettingsListTile(
            icon: item.icon,
            title: item.title,
            subtitle: item.subtitle,
            onTap: item.onTap,
            isDestructive: item.isDestructive,
          );
        },
      ),
    );
  }
}

class _WalletSettingsItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  _WalletSettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });
}
