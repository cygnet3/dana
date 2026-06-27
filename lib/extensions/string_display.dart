extension StringDisplay on String {
  /// Returns a shortened form with the middle elided for compact display.
  ///
  /// Shows the full string when [length] <= [maxFullLength]. Otherwise keeps
  /// [prefix] characters at the start and [suffix] at the end, separated by
  /// [ellipsis]. When [suffix] is 0, only the prefix and ellipsis are shown.
  String truncated({
    int prefix = 12,
    int suffix = 8,
    int? maxFullLength,
    String ellipsis = '…',
  }) {
    final threshold = maxFullLength ?? prefix + suffix;
    if (length <= threshold) return this;
    if (suffix <= 0) {
      return '${substring(0, prefix)}$ellipsis';
    }
    return '${substring(0, prefix)}$ellipsis${substring(length - suffix)}';
  }
}
