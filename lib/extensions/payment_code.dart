import 'dart:math';

import 'package:flutter/material.dart';

extension PaymentCode on String {
  /// Truncates the address to fit within [widthFraction] of the screen width,
  /// chunked into groups of 4 characters with the middle elided.
  String chunked(BuildContext context, TextStyle style, double widthFraction) {
    // split the address into chunks of size 4
    List<String> addrChunks = [];

    // if there is overflow, we add it to the first chunk
    int overflow = length % 4;
    addrChunks.add(substring(0, 4 + overflow));

    for (int i = 4 + overflow; i < length; i += 4) {
      int endIndex = min(i + 4, length);
      addrChunks.add(substring(i, endIndex));
    }

    // we take a fraction of the total screen width
    // this is the maximum size the address widget is allowed to be
    final maxWidth = MediaQuery.of(context).size.width * widthFraction;

    final chunkCount = _getChunkFittingWidth(addrChunks, style, maxWidth);

    // if all chunks fit, print everything
    if (addrChunks.length <= chunkCount) {
      return addrChunks.join(' ');
    }

    int firstHalfLength = ((chunkCount - 3).toDouble() / 2.0).ceil();
    int secondHalfLength = chunkCount - 3 - (firstHalfLength * 2);

    String firstHalfStr = addrChunks.sublist(0, firstHalfLength).join(' ');
    String secondHalfStr = addrChunks
        .sublist(addrChunks.length - firstHalfLength - secondHalfLength)
        .join(' ');

    return '$firstHalfStr  ...  $secondHalfStr';
  }
}

int _getChunkFittingWidth(List<String> chunks, TextStyle style, double width) {
  final TextPainter textPainter = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );

  int low = 1;
  int high = chunks.length;
  int best = 0;

  // we do a binary search to find the max number of chunks that fit within 'width'
  while (low <= high) {
    int mid = (low + high) ~/ 2;
    String subset = chunks.getRange(0, mid).join(' ');

    textPainter.text = TextSpan(text: subset, style: style);
    textPainter.layout();

    if (textPainter.width <= width) {
      best = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  return best;
}
