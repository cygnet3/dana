import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/screens/settings/about/about_screen.dart';
import 'package:danawallet/screens/settings/network/network_settings_screen.dart';
import 'package:danawallet/screens/settings/personalization/personalisation_settings_screen.dart';
import 'package:danawallet/screens/settings/widgets/settings_list_tile.dart';
import 'package:danawallet/widgets/skeletons/main_screen_skeleton.dart';
import 'package:danawallet/screens/settings/wallet/wallet_settings_screen.dart';
import 'package:flutter/material.dart';

const String pageTitle = "Settings";
const String networkSettingsTitle = "Network settings";
const String networkSettingsSubtitle = "Scanning, data usage, chain selection";
const String walletSettingsTitle = "Wallet settings";
const String walletSettingsSubtitle = "Backup, restore or wipe wallet";
const String personalizationSettingsTitle = "Personalization settings";
const String personalizationSettingsSubtitle =
    "Set language, bitcoin unit, fiat currency & theme";
const String aboutSettingsTitle = "About";
const String aboutSettingsSubtitle = "About Dana";

const IconData networkSettingsIcon = Icons.dns_outlined;
const IconData walletSettingsIcon = Icons.account_balance_wallet_outlined;
const IconData personalizationSettingsIcon = Icons.tune;
const IconData aboutSettingsIcon = Icons.info_outlined;

const Widget networkSettingScreen = NetworkSettingsScreen();
const Widget walletSettingsScreen = WalletSettingsScreen();
const Widget personalizationSettingsScreen = PersonalisationSettingsScreen();
const Widget aboutSettingsScreen = AboutSettingsScreen();

/// Main settings screen showing all setting categories
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsTiles = [
      SettingsListTile(
        icon: networkSettingsIcon,
        title: networkSettingsTitle,
        subtitle: networkSettingsSubtitle,
        onTap: () => goToScreen(context, networkSettingScreen),
      ),
      SettingsListTile(
        icon: walletSettingsIcon,
        title: walletSettingsTitle,
        subtitle: walletSettingsSubtitle,
        onTap: () => goToScreen(context, walletSettingsScreen),
      ),
      SettingsListTile(
        icon: personalizationSettingsIcon,
        title: personalizationSettingsTitle,
        subtitle: personalizationSettingsSubtitle,
        onTap: () => goToScreen(context, personalizationSettingsScreen),
      ),
      SettingsListTile(
        icon: aboutSettingsIcon,
        title: aboutSettingsTitle,
        subtitle: aboutSettingsSubtitle,
        onTap: () => goToScreen(context, aboutSettingsScreen),
      )
    ];

    return MainScreenSkeleton(
      showBackButton: false,
      title: pageTitle,
      body: ListView.separated(
        itemCount: settingsTiles.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          color: Bitcoin.neutral3,
          indent: 56,
        ),
        itemBuilder: (context, index) => settingsTiles[index],
      ),
    );
  }
}
