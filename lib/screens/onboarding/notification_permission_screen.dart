import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/screens/home/home.dart';
import 'package:danawallet/screens/onboarding/onboarding_skeleton.dart';
import 'package:danawallet/screens/onboarding/register_dana_address.dart';
import 'package:danawallet/states/permission_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';

const String _notificationPermissionBody =
    'Dana syncs your wallet in the background using an Android '
    'foreground service, which requires showing a notification while '
    'it runs.\n\nWithout this permission your wallet will only sync '
    'while the app is open, which may result in long sync times when '
    'you reopen the app.';

class NotificationPermissionScreen extends StatelessWidget {
  final bool goToDanaAddressSetup;

  const NotificationPermissionScreen({
    super.key,
    required this.goToDanaAddressSetup,
  });

  Future<void> _onContinue(BuildContext context) async {
    final permissions = Provider.of<PermissionState>(context, listen: false);
    await permissions.requestBackgroundSyncPermissions();

    if (context.mounted) {
      final nextScreen = goToDanaAddressSetup
          ? const RegisterDanaAddressScreen()
          : const HomeScreen();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => nextScreen),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.notifications_outlined,
                size: Adaptive.h(10),
                color: Bitcoin.black,
              ),
              SizedBox(height: Adaptive.h(3)),
              Text(
                'Allow notifications',
                style: BitcoinTextStyle.title3(Bitcoin.black).copyWith(
                  fontFamily: 'Inter',
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: Adaptive.h(2)),
              AutoSizeText(
                _notificationPermissionBody,
                style: BitcoinTextStyle.body3(Bitcoin.neutral7).copyWith(
                  fontFamily: 'Inter',
                ),
                textAlign: TextAlign.center,
                maxLines: 12,
              ),
            ],
          ),
        ),
      ],
    );

    final footer = FooterButton(
      title: 'Continue',
      onPressed: () => _onContinue(context),
    );

    return PopScope(
      canPop: false,
      child: OnboardingSkeleton(body: body, footer: footer),
    );
  }
}
