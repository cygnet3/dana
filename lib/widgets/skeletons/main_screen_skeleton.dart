import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/widgets/back_button.dart';
import 'package:flutter/material.dart';

/// Common layout structure for all settings screens
class MainScreenSkeleton extends StatelessWidget {
  final bool showBackButton;
  final String title;
  final Widget body;
  final Widget? footer;

  const MainScreenSkeleton({
    super.key,
    required this.showBackButton,
    required this.title,
    required this.body,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with optional back button
          if (showBackButton)
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: BackButtonWidget(),
            ),
          // Title
          Padding(
            padding: EdgeInsets.fromLTRB(16, showBackButton ? 8 : 16, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Bitcoin.neutral8,
              ),
            ),
          ),
          // Main content
          Expanded(child: body),
          // Optional footer
          if (footer != null) footer!,
        ],
      ),
    );
  }
}
