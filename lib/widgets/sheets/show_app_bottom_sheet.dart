import 'package:flutter/material.dart';

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final viewInsets = MediaQuery.viewInsetsOf(context);
      final viewPadding = MediaQuery.viewPaddingOf(context);
      return Padding(
        padding: EdgeInsets.only(
          bottom: viewInsets.bottom + viewPadding.bottom,
        ),
        child: builder(context),
      );
    },
  );
}
