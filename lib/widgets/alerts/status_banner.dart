import 'package:flutter/material.dart';

/// Generic inline status banner for persistent, non-blocking messages.
class StatusBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color backgroundColor;
  final Color foregroundColor;
  final EdgeInsetsGeometry padding;

  const StatusBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.backgroundColor,
    this.foregroundColor = Colors.white,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            ],
          ),
        ),
      ),
    );
  }
}
