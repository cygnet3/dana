import 'package:danawallet/constants.dart';
import 'package:flutter/material.dart';

class CircularIcon extends StatelessWidget {
  final Widget icon;
  final double radius;
  final Color color;

  const CircularIcon(
      {super.key,
      required this.icon,
      required this.radius,
      this.color = danaBlue});
  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: icon,
    );
  }
}
