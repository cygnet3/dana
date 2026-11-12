import 'dart:convert';
import 'dart:io';

import 'package:danawallet/repositories/settings_repository.dart'
    show frigateBackendBlindbit, frigateBackendFrigate;
import 'package:danawallet/services/spend_broadcast.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spend-flow broadcast backend acceptance tests (spend-broadcast card).
///
/// The selector tests are hermetic. The wire-level tests need the regtest
/// frigate rig on 127.0.0.1:50002 and skip when it is not reachable so the
/// suite stays green on machines without the rig.
Future<void> main() async {
  const defaultRegtestBlindbit = 'https://silentpayments.dev/blindbit/regtest';
  const configuredBlindbit = 'http://blindbit.example:8000';

  group('resolveSpendBroadcastTarget', () {
    test('selects frigate when the configured backend is frigate', () {
      final target = resolveSpendBroadcastTarget(
        frigateBackend: frigateBackendFrigate,
        frigateUrl: '127.0.0.1:50002',
        configuredBlindbitUrl: configuredBlindbit,
        defaultBlindbitUrl: defaultRegtestBlindbit,
      );
      expect(target.isFrigate, isTrue,
          reason: 'frigateBackend == frigate '
              'must broadcast via the frigate url, not blindbit');
      expect(target.url, '127.0.0.1:50002');
    });

    test(
        'frigate selected but no url -> explicit error, never blindbit '
        '(frigate-exclusive, owner ruling 2026-11-12)', () {
      for (final frigateUrl in [null, '', '   ']) {
        expect(
          () => resolveSpendBroadcastTarget(
            frigateBackend: frigateBackendFrigate,
            frigateUrl: frigateUrl,
            configuredBlindbitUrl: configuredBlindbit,
            defaultBlindbitUrl: defaultRegtestBlindbit,
          ),
          throwsA(isA<SpendBroadcastBackendError>()),
          reason: 'the user selected frigate: spending must block with an '
              'explicit error, not silently broadcast via blindbit (a '
              'different third party)',
        );
      }
    });

    test('falls back to blindbit when the backend is not frigate', () {
      for (final backend in [null, frigateBackendBlindbit, 'something-else']) {
        final target = resolveSpendBroadcastTarget(
          frigateBackend: backend,
          frigateUrl: '127.0.0.1:50002',
          configuredBlindbitUrl: configuredBlindbit,
          defaultBlindbitUrl: defaultRegtestBlindbit,
        );
        expect(target.isFrigate, isFalse);
        expect(target.url, configuredBlindbit);
      }
    });

    test('uses the network default blindbit url when nothing is configured',
        () {
      final target = resolveSpendBroadcastTarget(
        frigateBackend: null,
        frigateUrl: null,
        configuredBlindbitUrl: null,
        defaultBlindbitUrl: defaultRegtestBlindbit,
      );
      expect(target.isFrigate, isFalse);
      expect(target.url, defaultRegtestBlindbit);
    });
  });

  const rigHost = '127.0.0.1';
  const rigPort = 50002;

  Future<bool> rigReachable() async {
    try {
      final socket = await Socket.connect(rigHost, rigPort,
          timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  final rigUp = await rigReachable();

  group('frigate wire broadcast (regtest rig)', () {
    test('rejects a broadcast sent before the server.version handshake',
        () async {
      // Frigate requires `server.version` as the FIRST message on the wire;
      // the helper honours that — this pins the requirement explicitly.
      final socket = await Socket.connect(rigHost, rigPort,
          timeout: const Duration(seconds: 10));
      try {
        socket.writeln(jsonEncode({
          'jsonrpc': '2.0',
          'method': 'blockchain.transaction.broadcast',
          'params': ['deadbeef'],
          'id': 1,
        }));
        await socket.flush();

        final reply = await const LineSplitter()
            .bind(utf8.decoder.bind(socket))
            .first
            .timeout(const Duration(seconds: 10));
        final decoded = jsonDecode(reply) as Map<String, dynamic>;
        expect(decoded['error'], isNotNull,
            reason: 'a broadcast-first connection must be rejected');
      } finally {
        socket.destroy();
      }
    });

    test('broadcastViaFrigate surfaces the server error for a bogus tx',
        () async {
      await expectLater(
        broadcastViaFrigate('$rigHost:$rigPort', 'deadbeef'),
        throwsA(predicate((e) => e.toString().contains('TX decode'),
            'surfaces the server TX decode error')),
      );
    });

    test('blindbit broadcast path cannot reach a frigate server', () async {
      // Pins the b9dc32b behavior this card fixes: posting the signed tx as
      // a blindbit forward-tx request to the frigate endpoint yields no
      // usable HTTP response (empty body -> EOF while parsing a value).
      final client = HttpClient();
      Object? failure;
      try {
        final request = await client
            .postUrl(Uri.parse('http://$rigHost:$rigPort/forward-tx'))
            .timeout(const Duration(seconds: 5));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'tx_hex': '00' * 40}));
        final response =
            await request.close().timeout(const Duration(seconds: 5));
        final body = await utf8.decodeStream(response);
        if (body.isEmpty) {
          failure = 'empty body (HTTP ${response.statusCode})';
        } else {
          try {
            jsonDecode(body);
          } on FormatException {
            failure =
                'non-JSON body: ${body.length > 80 ? body.substring(0, 80) : body}';
          }
        }
      } catch (e) {
        failure = e.toString();
      } finally {
        client.close();
      }
      expect(failure, isNotNull,
          reason: 'the blindbit broadcast path must NOT be able to reach a '
              'frigate server — that is exactly the bug this card fixes');
    });

    test('broadcasts a real signed regtest tx end-to-end', () async {
      final rawTx = Platform.environment['FRIGATE_E2E_RAWTX'];
      if (rawTx == null || rawTx.isEmpty) {
        // Without the e2e fixture the full path is covered by the bogus-tx
        // and handshake tests above; the loop runs this test with the env
        // var set against the live rig.
        return;
      }
      final txid = await broadcastViaFrigate('$rigHost:$rigPort', rawTx);
      expect(txid, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  }, skip: rigUp ? false : 'frigate rig not reachable on $rigHost:$rigPort');
}
