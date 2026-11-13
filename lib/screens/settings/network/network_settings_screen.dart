import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/screens/settings/network/frigate_settings_screen.dart';
import 'package:danawallet/screens/settings/widgets/settings_list_tile.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/services/sync_orchestrator.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class NetworkSettingsScreen extends StatelessWidget {
  const NetworkSettingsScreen({super.key});

  List<_NetworkSettingsItem> _buildItems(BuildContext context) {
    return [
      _NetworkSettingsItem(
        icon: Icons.radar,
        title: 'Set backend url',
        subtitle: 'Optional frigate sync server & visibility',
        onTap: () => goToScreen(context, const FrigateSettingsScreen()),
      ),
      if (isDevEnv)
        _NetworkSettingsItem(
          icon: Icons.schedule,
          title: 'Set sync height',
          subtitle: 'Reset blockchain sync position',
          onTap: () => _onSetLastSync(context),
        ),
      if (isDevEnv)
        _NetworkSettingsItem(
          icon: Icons.filter_list,
          title: 'Set dust threshold',
          subtitle: 'Ignore payments below this value',
          onTap: () => _onSetDustLimit(context),
        ),
    ];
  }

  Future<void> _onSetLastSync(BuildContext context) async {
    final walletState = Provider.of<WalletState>(context, listen: false);
    final orchestrator = Provider.of<SyncOrchestrator>(context, listen: false);

    TextEditingController controller = TextEditingController();
    final syncHeight = await showInputAlertDialog(
        controller,
        TextInputType.number,
        'Enter sync height',
        'Enter current sync height (numeric value)');

    if (syncHeight is! int && syncHeight != true) return;

    await orchestrator.stop();

    if (syncHeight is int) {
      await walletState.resetToSyncHeight(syncHeight);
    } else {
      await walletState.resetToBirthday();
    }

    await orchestrator.start();

    if (context.mounted) goToHomeScreen(context);
  }

  Future<void> _onSetDustLimit(BuildContext context) async {
    SettingsRepository settings = SettingsRepository.instance;
    final controller = TextEditingController();
    final dustLimit = await settings.getDustLimit();
    if (dustLimit != null) {
      controller.text = dustLimit.toString();
    } else {
      controller.text = '';
    }

    final value = await showInputAlertDialog(controller, TextInputType.number,
        'Set dust limit', 'Payments below this value are ignored');

    if (value is int) {
      Logger().i("setting dust limit to $value");
      await settings.setDustLimit(value);
    } else if (value is bool && value) {
      Logger().i("resetting dust limit to default");
      await settings.setDustLimit(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(context);

    return ScreenSkeleton(
      showBackButton: true,
      title: 'Network settings',
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
          );
        },
      ),
    );
  }
}

class _NetworkSettingsItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _NetworkSettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}
