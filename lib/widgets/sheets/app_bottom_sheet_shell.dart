import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/widgets/sheets/sheet_handle_bar.dart';
import 'package:flutter/material.dart';

class AppBottomSheetShell extends StatelessWidget {
  const AppBottomSheetShell({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.all(25.0),
    this.backgroundColor = Colors.white,
  });

  static const borderRadius = BorderRadius.vertical(top: Radius.circular(20));

  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandleBar(),
          if (title != null) ...[
            Text(title!, style: BitcoinTextStyle.title4(Bitcoin.black)),
            const SizedBox(height: 20),
          ],
          child,
        ],
      ),
    );
  }
}
