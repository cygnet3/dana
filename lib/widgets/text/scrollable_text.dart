import 'package:flutter/material.dart';
import 'package:text_scroll/text_scroll.dart';

class ScrollableText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const ScrollableText({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return TextScroll(text,
        mode: TextScrollMode.bouncing,
        delayBefore: const Duration(milliseconds: 1500),
        pauseOnBounce: const Duration(milliseconds: 1000),
        pauseBetween: const Duration(milliseconds: 1000),
        textAlign: TextAlign.end,
        style: style);
  }
}
