import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/screens/settings/personalization/change_fiat_screen.dart';
import 'package:danawallet/screens/settings/widgets/settings_list_tile.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/home_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PersonalisationSettingsScreen extends StatelessWidget {
  const PersonalisationSettingsScreen({super.key});

  List<_PersonalisationSettingsItem> _buildItems(BuildContext context) {
    return [
      _PersonalisationSettingsItem(
        icon: Icons.currency_exchange,
        title: 'Change fiat currency',
        subtitle: 'Set your preferred fiat currency',
        onTap: () => _onChangeFiat(context),
      ),
    ];
  }

  // Business logic methods
  void _onChangeFiat(BuildContext context) async {
    final fiatExchangeRate =
        Provider.of<FiatExchangeRateState>(context, listen: false);
    final currentCurrency =
        (await SettingsRepository.instance.getFiatCurrency()) ??
            defaultCurrency;
    if (context.mounted) {
      goToScreen(
          context,
          ChangeFiatScreen(
              currentCurrency: currentCurrency,
              onConfirm: (chosen) async {
                await fiatExchangeRate.updateCurrency(chosen);

                if (context.mounted) {
                  goToHomeScreen(context);
                }
              }));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(context);

    return ScreenSkeleton(
      showBackButton: true,
      title: 'Personalisation settings',
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

class _PersonalisationSettingsItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _PersonalisationSettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}
