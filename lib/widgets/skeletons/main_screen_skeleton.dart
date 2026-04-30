import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:flutter/material.dart';

/// Common layout structure for all settings screens
class MainScreenSkeleton extends StatelessWidget {
  final Widget body;
  final String? title;
  final Widget? footer;
  final AppBar? appBar;
  final VoidCallback? floatingAction;

  const MainScreenSkeleton({
    super.key,
    this.title,
    required this.body,
    this.footer,
    this.appBar,
    this.floatingAction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      floatingActionButton: (floatingAction != null)
          ? FloatingActionButton(
              onPressed: floatingAction,
              backgroundColor: Bitcoin.blue,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: SafeArea(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                title!,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Bitcoin.neutral8,
                ),
              ),
            ),
          // Main content
          Expanded(
              child: Padding(
                  padding: const EdgeInsetsGeometry.symmetric(
                      horizontal: 20, vertical: 5),
                  child: body)),
          // Optional footer
          if (footer != null) footer!,
        ],
      )),
    );
  }
}
