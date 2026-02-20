extension DateTimeExtension on DateTime {
  int toSeconds() => millisecondsSinceEpoch ~/ 1000;
}

extension TimestampExtension on int {
  DateTime toDate() {
    const max32BitUnsigned = 4294967295; // 2^32 - 1

    if (this < 0) {
      throw ArgumentError(
        'Timestamp cannot be negative: $this',
      );
    }

    if (this > max32BitUnsigned) {
      throw ArgumentError(
        'Timestamp exceeds 32-bit unsigned int range: $this. Maximum value is $max32BitUnsigned',
      );
    }

    return DateTime.fromMillisecondsSinceEpoch(this * 1000, isUtc: true);
  }
}
