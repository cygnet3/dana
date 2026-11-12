import 'package:danawallet/generated/rust/api/wallet/frigate.dart'
    show frigateTipProbe;
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/screens/settings/network/frigate_url_dialog.dart';
import 'package:danawallet/screens/settings/widgets/settings_list_tile.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

/// Frigate sync backend settings (D5, D6, D7, D9, D10).
///
/// Save flow (D10): parse -> keyless tip probe -> chain-consistency check
/// (backend network must equal the wallet's network) -> inline error on any
/// failure, do not persist. The probe is `frigateTipProbe` — connect +
/// version handshake + `blockchain.block.header(0)` (genesis identification)
/// + `blockchain.headers.subscribe` only, no scan key anywhere on that path.
/// [SyncEngine]'s `syncViaFrigate` is never reachable from here.
class FrigateSettingsScreen extends StatelessWidget {
  const FrigateSettingsScreen({super.key});

  List<_FrigateSettingsItem> _buildItems(BuildContext context) {
    return [
      _FrigateSettingsItem(
        icon: Icons.swap_horiz,
        title: 'Sync backend',
        subtitle: 'blindbit (default) or frigate',
        onTap: () => _onSelectBackend(context),
      ),
      _FrigateSettingsItem(
        icon: Icons.dns_outlined,
        title: 'Set frigate url',
        subtitle: 'host:port or ssl://host:port',
        onTap: () => _onSetFrigateUrl(context),
      ),
    ];
  }

  /// D9 explicit backend switch. Switching while a scan runs interrupts it
  /// through the existing interrupt path: the frigate outcome becomes
  /// `Disconnected{"interrupted"}` without finalize (commit to the last
  /// Confirmed boundary) and blindbit resumes from there on the next wake.
  Future<void> _onSelectBackend(BuildContext context) async {
    final settings = SettingsRepository.instance;
    final current =
        await settings.getFrigateBackend() ?? frigateBackendBlindbit;

    if (!context.mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Select sync backend'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, frigateBackendBlindbit),
            child: const Text('blindbit (default)'),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, frigateBackendFrigate),
            child: const Text('frigate'),
          ),
        ],
      ),
    );

    if (selected == null || selected == current) return;
    await settings.setFrigateBackend(selected);
    displayNotification('Sync backend set to $selected');

    // Mid-scan switch (D9): interrupt the running scan via the existing
    // path. No-op when idle.
    if (context.mounted) {
      final syncProgress =
          Provider.of<SyncProgressState>(context, listen: false);
      if (syncProgress.isSyncing) {
        Logger().i('interrupting active scan after backend switch');
        await syncProgress.interruptSync();
      }
    }
  }

  Future<String?> _pickVisibility(BuildContext context, String current) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Who runs this server?'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, frigateVisibilityPrivate),
            child: Text(
              'Private (recommended)\nOnly you or a trusted party run it',
              style: current == frigateVisibilityPrivate
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, frigateVisibilityPublic),
            child: Text(
              'Public\nOperated by a third party',
              style: current == frigateVisibilityPublic
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Minimal client-side shape check before the probe; the authoritative
  /// validation is the keyless reachability probe itself (D10).
  String? validateFrigateUrl(String input) {
    final url = input.trim();
    if (url.isEmpty) return 'URL is empty';
    if (url.contains(RegExp(r'\s'))) return 'URL must not contain spaces';
    if (!url.contains(':')) {
      return 'Expected host:port or ssl://host:port';
    }
    return null;
  }

  /// D10 save flow: parse -> probe -> warn (public) -> persist. Any failure
  /// leaves the stored URL untouched. Parse/probe/chain failures are
  /// reported as a persistent inline error INSIDE the URL dialog (finding
  /// t_3ba59c28): the dialog stays open, the entered text is preserved, and
  /// the raw Rust exception never leaks into a transient snackbar.
  Future<void> _onSetFrigateUrl(BuildContext context) async {
    final settings = SettingsRepository.instance;
    final walletRepository = WalletRepository.instance;
    final controller = TextEditingController();
    controller.text = await settings.getFrigateUrl() ?? '';

    if (!context.mounted) return;
    final value = await showDialog<dynamic>(
      context: context,
      builder: (dialogContext) => FrigateUrlDialog(
        controller: controller,
        titleText: 'Set frigate url',
        labelText: 'host:port or ssl://host:port',
        validate: (input) async {
          final parseError = validateFrigateUrl(input);
          if (parseError != null) {
            return 'Invalid frigate url: $parseError';
          }

          // D10 reachability probe — keyless by construction. On failure
          // the URL is NOT persisted (the dialog stays open instead). The
          // probe also identifies the chain the backend follows (genesis
          // hash); a backend on another chain is refused with an explicit
          // error — a foreign-chain frigate silently wedges payment
          // discovery until the sync height is manually reset.
          try {
            final probe = await frigateTipProbe(url: input.trim());
            final walletNetwork = await walletRepository.readNetwork();
            if (probe.network != walletNetwork) {
              return 'Frigate server is on ${probe.network.name} but this '
                  'wallet is on ${walletNetwork.name}';
            }
            Logger().i('frigate probe ok, tip at ${probe.tipHeight} on '
                '${probe.network.name}');
            return null;
          } catch (e) {
            return frigateProbeFailureMessage(e);
          }
        },
      ),
    );

    if (value is bool && value) {
      Logger().i('resetting frigate url');
      await settings.setFrigateUrl(null);
      await settings.setFrigateVisibility(null);
      displayNotification('Frigate url cleared (blindbit stays active)');
      return;
    }
    if (value is! String) return;

    if (!context.mounted) return;
    final currentVisibility =
        await settings.getFrigateVisibility() ?? frigateVisibilityPrivate;
    if (!context.mounted) return;
    final visibility = await _pickVisibility(context, currentVisibility);
    if (visibility == null) return;

    // D6: the public warning fires exactly once per wallet — the first
    // declaration of ANY public instance. A later public URL adds nothing
    // to what is already lost, so no second dialog (D7).
    if (visibility == frigateVisibilityPublic &&
        !await walletRepository.readFrigatePublicWarned()) {
      if (!context.mounted) return;
      final confirmed = await showConfirmationAlertDialog(
        'Use a public frigate server?',
        'You chose a PUBLIC frigate server. Two distinct harms:\n\n'
            '1. The server learns your scan key together with every output it '
            'reports, permanently linking your historical silent-payment '
            'outputs to that server.\n\n'
            '2. The server can keep observing your wallet\u2019s ongoing '
            'activity, and that observation survives rotating your payment '
            'keys.\n\n'
            'A private server carries a strictly milder version of the first '
            'risk, limited to an operator you choose to trust.',
      );
      if (!confirmed) {
        displayNotification('Frigate url not saved');
        return;
      }
      await walletRepository.markFrigatePublicWarned();
      // The declaration itself is a disclosure decision: record it.
      await walletRepository.appendFrigateDisclosureRecord(
          url: value.trim(), visibility: frigateVisibilityPublic);
    }

    await settings.setFrigateUrl(value.trim());
    await settings.setFrigateVisibility(visibility);
    displayNotification('Frigate url saved ($visibility): ${value.trim()}');
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(context);

    return ScreenSkeleton(
      showBackButton: true,
      title: 'Frigate backend',
      body: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (context, index) => const Divider(
          height: 1,
          thickness: 1,
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

class _FrigateSettingsItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _FrigateSettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}
