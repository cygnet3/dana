import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:flutter/material.dart';

class SheetHandleBar extends StatelessWidget {
  const SheetHandleBar({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: margin ?? const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Bitcoin.neutral4,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
