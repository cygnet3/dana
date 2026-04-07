import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/widgets/back_button.dart';
import 'package:flutter/material.dart';

// This is the main screen template widget.
// Generally, this template should be used across all full-sized screens,
// in order to make things like padding and button placement consistent.
class ScreenSkeleton extends StatelessWidget {
  final bool showBackButton;
  final String? title;
  final Widget body;
  final Widget? footer;
  final Widget? floatingActionButton;

  const ScreenSkeleton({
    super.key,
    this.title,
    required this.body,
    this.footer,
    this.floatingActionButton,
    required this.showBackButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: showBackButton ? const BackButtonWidget() : null,
        ),
        floatingActionButton: floatingActionButton,
        body: Padding(
            padding: const EdgeInsets.all(25.0),
            child: Column(
              children: [
                if (title != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(title!,
                        style: BitcoinTextStyle.title4(Bitcoin.black)),
                  ),
                Flexible(child: body),
                if (footer != null) footer!,
              ],
            )));
  }
}
