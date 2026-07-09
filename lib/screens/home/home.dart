import 'dart:async';

import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:danawallet/states/home_state.dart';
import 'package:danawallet/screens/contacts/contacts.dart';
import 'package:danawallet/screens/wallet/wallet.dart';
import 'package:danawallet/screens/settings/settings_screen.dart';
import 'package:danawallet/states/permission_state.dart';
import 'package:danawallet/widgets/alerts/status_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const Color bgSyncUnavailableColor = Color(0xFF1565C0);
const String bgSyncUnavailableMsg = "Background syncing not available";

class HomeScreen extends StatelessWidget {
  static const List<Widget> _widgetOptions = [
    WalletScreen(),
    ContactsScreen(),
    SettingsScreen(),
  ];

  const HomeScreen({super.key});

  Future<void> _onEnableBackgroundSync(BuildContext context) async {
    final permissionState =
        Provider.of<PermissionState>(context, listen: false);
    if (!await permissionState.requestPermissionsAndWaitForSettingsReturn()) {
      displayWarning(
          'Notification permission is required for background sync.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeState = Provider.of<HomeState>(context, listen: true);
    final permissions = Provider.of<PermissionState>(context, listen: true);

    return PopScope(
        canPop: false,
        child: Scaffold(
          body: Column(
            children: [
              if (!permissions.notificationGranted)
                StatusBanner(
                  icon: Icons.sync,
                  message: bgSyncUnavailableMsg,
                  backgroundColor: bgSyncUnavailableColor,
                  actionLabel: 'Enable',
                  onActionPressed: () {
                    unawaited(_onEnableBackgroundSync(context));
                  },
                ),
              Expanded(
                child: IndexedStack(
                  index: homeState.selectedIndex,
                  children: _widgetOptions,
                ),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: Image(
                    image: const AssetImage("icons/flip_vertical.png",
                        package: "bitcoin_ui"),
                    color: Bitcoin.neutral7),
                activeIcon: Image(
                    image: const AssetImage("icons/flip_vertical.png",
                        package: "bitcoin_ui"),
                    color: Bitcoin.blue),
                label: 'Transact',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.contacts, color: Bitcoin.neutral7),
                activeIcon: Icon(Icons.contacts, color: Bitcoin.blue),
                label: 'Contacts',
              ),
              BottomNavigationBarItem(
                icon: Image(
                    image: const AssetImage("icons/gear.png",
                        package: "bitcoin_ui"),
                    color: Bitcoin.neutral7),
                activeIcon: Image(
                    image: const AssetImage("icons/gear.png",
                        package: "bitcoin_ui"),
                    color: Bitcoin.blue),
                label: 'Settings',
              ),
            ],
            currentIndex: homeState.selectedIndex,
            selectedItemColor: Bitcoin.blue,
            onTap: (index) {
              if (index == 0) {
                unawaited(context
                    .read<FiatExchangeRateState>()
                    .updateExchangeRates());
              }

              homeState.setIndex(index);
            },
          ),
        ));
  }
}
