import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:danawallet/repositories/settings_repository.dart'
    show frigateBackendFrigate;

/// Where the spend flow broadcasts a signed transaction.
class SpendBroadcastTarget {
  const SpendBroadcastTarget.frigate(this.url) : isFrigate = true;
  const SpendBroadcastTarget.blindbit(this.url) : isFrigate = false;

  final bool isFrigate;

  /// The frigate url (bare host:port) or the blindbit url to broadcast to.
  final String url;
}

/// Decides how the spend flow broadcasts, consuming the same frigate-
/// exclusive rule as the sync engine's per-cycle resolution (owner ruling
/// 2026-11-12): frigate when the user selected it AND a url is configured;
/// blindbit only as the default backend; frigate-selected-but-unconfigured
/// throws an explicit [SpendBroadcastBackendError] — never a silent
/// blindbit fallback (a different third party, different disclosure).
SpendBroadcastTarget resolveSpendBroadcastTarget({
  required String? frigateBackend,
  required String? frigateUrl,
  required String? configuredBlindbitUrl,
  required String defaultBlindbitUrl,
}) {
  final url = frigateUrl?.trim();
  if (frigateBackend == frigateBackendFrigate) {
    if (url == null || url.isEmpty) {
      throw const SpendBroadcastBackendError(
          'Frigate backend selected but no frigate url is configured — set '
          'one in settings. Nothing was broadcast.');
    }
    return SpendBroadcastTarget.frigate(url);
  }
  return SpendBroadcastTarget.blindbit(
      configuredBlindbitUrl ?? defaultBlindbitUrl);
}

/// The selected backend cannot carry the broadcast (e.g. frigate selected
/// with no url configured). Surfaced verbatim to the user — never a silent
/// fallback to another backend.
class SpendBroadcastBackendError implements Exception {
  final String message;
  const SpendBroadcastBackendError(this.message);
  @override
  String toString() => message;
}

/// Broadcast a raw transaction to a frigate (Electrum-protocol) server.
///
/// The frigate backend implements the standard Electrum method
/// `blockchain.transaction.broadcast` (requires `server.version` as the first
/// message on the connection). The sync path never uses it, but the spend
/// path needs it when the wallet's configured backend is frigate — the
/// blindbit-only broadcast path cannot reach a frigate server.
Future<String> broadcastViaFrigate(
  String url,
  String rawTx, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final colon = url.lastIndexOf(':');
  if (colon <= 0 || colon == url.length - 1) {
    throw Exception('Invalid frigate url for broadcast: $url');
  }
  final port = int.tryParse(url.substring(colon + 1));
  if (port == null) {
    throw Exception('Invalid frigate port in url: $url');
  }
  final host = url.substring(0, colon);

  final socket = await Socket.connect(host, port, timeout: timeout);
  try {
    socket.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'method': 'server.version',
      'params': ['dana', '1.4'],
      'id': 1,
    }));
    socket.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'method': 'blockchain.transaction.broadcast',
      'params': [rawTx],
      'id': 2,
    }));
    await socket.flush();

    final lines = const LineSplitter()
        .bind(utf8.decoder.bind(socket))
        .timeout(timeout, onTimeout: (sink) {
      sink.addError(Exception('Frigate broadcast timed out'));
      sink.close();
    });

    await for (final line in lines) {
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } catch (_) {
        continue;
      }
      if (decoded is Map<String, dynamic> && decoded['id'] == 2) {
        if (decoded['error'] != null) {
          throw Exception('Frigate broadcast error: ${decoded['error']}');
        }
        final result = decoded['result'];
        if (result is String) {
          return result;
        }
        throw Exception('Unexpected frigate broadcast response: $line');
      }
    }
    throw Exception(
        'Frigate closed the connection before a broadcast response');
  } finally {
    socket.destroy();
  }
}
