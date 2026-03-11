import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/screens/settings/widgets/settings_list_tile.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/home_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class NetworkSettingsScreen extends StatelessWidget {
  const NetworkSettingsScreen({super.key});

  List<_NetworkSettingsItem> _buildItems(BuildContext context) {
    return [
      _NetworkSettingsItem(
        icon: Icons.dns_outlined,
        title: 'Set backend url',
        subtitle: 'Configure blindbit server endpoint',
        onTap: () => _onSetBlindbitUrl(context),
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
    final homeState = Provider.of<HomeState>(context, listen: false);
    final chainState = Provider.of<ChainState>(context, listen: false);

    TextEditingController controller = TextEditingController();
    final syncHeight = await showInputAlertDialog(
        controller,
        TextInputType.number,
        'Enter sync height',
        'Enter current sync height (numeric value)');
    if (syncHeight is int) {
      await walletState.resetToSyncHeight(syncHeight);
      chainState.clearSyncHistory();
      homeState.showMainScreen();
    } else if (syncHeight is bool && syncHeight) {
      final birthday = walletState.birthday;
      // TODO probably better and simpler to set lastScan to null and let the synchronization service set it to the birthday height
      final height = await chainState.getBlockHeightFromDate(birthday!);
      await walletState.resetToSyncHeight(height);
      chainState.clearSyncHistory();
      homeState.showMainScreen();
    }
  }

  Future<void> _onSetBlindbitUrl(BuildContext context) async {
    SettingsRepository settings = SettingsRepository.instance;
    final chainState = Provider.of<ChainState>(context, listen: false);
    final controller = TextEditingController();
    controller.text = await settings.getBlindbitUrl() ?? '';

    final value = await showInputAlertDialog(controller, TextInputType.url,
        'Set blindbit url', 'Only blindbit is currently supported');

    if (value is String) {
      final success = await chainState.updateBlindbitUrl(value);
      if (success) {
        displayNotification("Setting blindbit url to $value");
        await settings.setBlindbitUrl(value);
      } else {
        displayWarning("Failed to update blindbit url");
      }
    } else if (value is bool && value) {
      Logger().i("resetting blindbit url to default");
      await settings.setBlindbitUrl(null);
      await chainState.resetBlindbitUrl();
    }
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
