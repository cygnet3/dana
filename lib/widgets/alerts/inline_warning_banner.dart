import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:flutter/material.dart';

/// Compact inline warning for persistent, non-blocking messages inside a screen.
class InlineWarningBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  const InlineWarningBanner({
    super.key,
    required this.message,
    this.icon = Icons.warning_amber_rounded,
    this.actionLabel,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Bitcoin.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Bitcoin.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Bitcoin.orange, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: BitcoinTextStyle.body5(Bitcoin.orange),
            ),
          ),
          if (actionLabel != null && onActionPressed != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onActionPressed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Bitcoin.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  actionLabel!,
                  style: BitcoinTextStyle.body5(Bitcoin.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
