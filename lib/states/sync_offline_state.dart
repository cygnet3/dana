import 'package:flutter/foundation.dart';

/// Holds the transient neutral banner message for an unreachable frigate
/// server (D8). Set by the sync engine host (directly in-process or via the
/// [bgKeyFrigateOffline] IPC key from the background isolate), cleared on the
/// next successful sync. No red error, no blindbit fallback.
class SyncOfflineState extends ChangeNotifier {
  String? _message;

  /// Null when there is nothing to report.
  String? get message => _message;

  void setOffline(String message) {
    if (_message == message) return;
    _message = message;
    notifyListeners();
  }

  void clear() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }
}
