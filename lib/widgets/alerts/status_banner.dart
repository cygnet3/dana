import 'package:flutter/material.dart';

/// Generic inline status banner for persistent, non-blocking messages.
class StatusBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color backgroundColor;
  final Color foregroundColor;
  final EdgeInsetsGeometry padding;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  const StatusBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.backgroundColor,
    this.foregroundColor = Colors.white,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.actionLabel,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Material(
        color: backgroundColor,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              Icon(icon, color: foregroundColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: foregroundColor, fontSize: 13),
                ),
              ),
              if (actionLabel != null && onActionPressed != null)
                Container(
                  margin: const EdgeInsets.only(left: 10),
                  child: ElevatedButton(
                    onPressed: onActionPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: foregroundColor,
                      foregroundColor: backgroundColor,
                      elevation: 0,
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(actionLabel!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
