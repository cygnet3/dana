import 'dart:async';

import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/settings/personalization/change_amount_display_screen.dart';
import 'package:danawallet/screens/settings/personalization/change_fiat_screen.dart';
import 'package:danawallet/screens/settings/widgets/settings_list_tile.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/states/display_preferences_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PersonalisationSettingsScreen extends StatelessWidget {
  const PersonalisationSettingsScreen({super.key});

  List<_PersonalisationSettingsItem> _buildItems(BuildContext context) {
    return [
      _PersonalisationSettingsItem(
        icon: Icons.currency_bitcoin,
        title: 'Bitcoin unit',
        subtitle: 'Preferred unit for displaying bitcoin amounts',
        onTap: () => _onChangeAmountDisplay(context),
      ),
      _PersonalisationSettingsItem(
        icon: Icons.currency_exchange,
        title: 'Fiat currency',
        subtitle: 'Preferred fiat currency for conversion',
        onTap: () => _onChangeFiat(context),
      ),
    ];
  }

  void _onChangeAmountDisplay(BuildContext context) async {
    final displayPreferences =
        Provider.of<DisplayPreferencesState>(context, listen: false);
    if (context.mounted) {
      goToScreen(
          context,
          ChangeAmountDisplayScreen(
              currentUnit: displayPreferences.amountDisplayUnit,
              onConfirm: (chosen) async {
                await displayPreferences.updateAmountDisplayUnit(chosen);

                if (context.mounted) {
                  Navigator.pop(context);
                }
              }));
    }
  }

  void _onChangeFiat(BuildContext context) async {
    final displayPreferences =
        Provider.of<DisplayPreferencesState>(context, listen: false);
    final fiatExchangeRate =
        Provider.of<FiatExchangeRateState>(context, listen: false);
    if (context.mounted) {
      goToScreen(
          context,
          ChangeFiatScreen(
              currentCurrency: displayPreferences.fiatCurrency,
              onConfirm: (chosen) async {
                await displayPreferences.updateFiatCurrency(chosen);
                unawaited(fiatExchangeRate.updateExchangeRates());

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
