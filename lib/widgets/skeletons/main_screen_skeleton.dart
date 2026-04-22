import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:flutter/material.dart';

/// Common layout structure for all settings screens
class MainScreenSkeleton extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? footer;
  final AppBar? appBar;
  final VoidCallback? floatingAction;

  const MainScreenSkeleton({
    super.key,
    required this.title,
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
          Expanded(
              child: Padding(
                  padding: const EdgeInsetsGeometry.all(10), child: body)),
          // Optional footer
          if (footer != null) footer!,
        ],
      ),
    );
  }
}
