import 'package:flutter/material.dart';

class OnboardingSkeleton extends StatelessWidget {
  final Widget body;
  final Widget footer;
  const OnboardingSkeleton({
    super.key,
    required this.body,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(25, 0, 25, 25),
          child: Column(
            children: [
              Expanded(child: body),
              footer,
            ],
          ),
        ),
      ),
    );
  }
}
