import 'dart:convert';

import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/repositories/name_server_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

/// Table-driven coverage for the client-side binding validation in
/// [NameServerRepository.requestChallenge] (finding t_972f6cc3): a
/// buggy/compromised nameserver must not be able to hand back a
/// `dana-register:{network_key}:{nonce}:{user_name}:{domain}` message whose
/// fields differ from what the user actually requested, because that exact
/// string is what goes on to be signed by the spend key.
///
/// Fake HTTP layer: MockClient from the existing `http` dependency
/// (`package:http/testing.dart`) injected through the repository's `client`
/// seam — the same route as the sibling repository tests.
const String _userName = 'alice';
const String _domain = 'danawallet.app';
const String _networkKey = '9f2c7a4e';
const String _nonce = 'deadbeef';
const String _spAddress = 'sp1qqernutv8ar5g7m2x';
const String _requestId = 'req-1';

/// The honest server message for the constants above, in the server's exact
/// field order (dana-nameserver `challenge_message()`).
String _validMessage() =>
    'dana-register:$_networkKey:$_nonce:$_userName:$_domain';

/// POST /challenge responder with overridable fields; each override stays
/// internally consistent (the `nonce`/`network_key` JSON fields follow the
/// arguments), so a tampered `message` is the only thing that is dishonest.
MockClient _challengeClient({
  String? message,
  String? networkKey = _networkKey,
  String? nonce = _nonce,
}) {
  return MockClient((request) async {
    final body = <String, dynamic>{'id': _requestId};
    if (message != null) body['message'] = message;
    if (nonce != null) body['nonce'] = nonce;
    if (networkKey != null) body['network_key'] = networkKey;
    body['expires_at'] = 1791036000;
    return Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json'});
  });
}

NameServerRepository _repoWith(MockClient client) {
  final repo = NameServerRepository(network: Network.signet);
  repo.client = () => client;
  return repo;
}

/// Runs requestChallenge against [client] and returns the thrown object, or
/// null when it completed.
Future<Object?> _captureError(MockClient client) async {
  try {
    await _repoWith(client).requestChallenge(
      userName: _userName,
      domain: _domain,
      spAddress: _spAddress,
      requestId: _requestId,
    );
    return null;
  } catch (e) {
    return e;
  }
}

void main() {
  group('requestChallenge binding validation', () {
    test('all-fields-equal => returns; server bytes pass through verbatim',
        () async {
      final serverMessage = _validMessage();
      final repo = _repoWith(_challengeClient(message: serverMessage));

      final challenge = await repo.requestChallenge(
        userName: _userName,
        domain: _domain,
        spAddress: _spAddress,
        requestId: _requestId,
      );

      // Validation-only contract: what we hand on to signing is the exact
      // bytes the server returned, never the client-reassembled string.
      expect(challenge.message, serverMessage);
      expect(challenge.nonce, _nonce);
      expect(challenge.networkKey, _networkKey);
    });

    // Each row tampers exactly one aspect of an otherwise-honest message.
    final fieldsJoinedByUnderscores = [
      _networkKey,
      _nonce,
      _userName,
      _domain,
    ].join('_');
    final tampered = <String, String>{
      'domain swapped for an attacker domain':
          'dana-register:$_networkKey:$_nonce:$_userName:evil.example',
      'user_name swapped for another user':
          'dana-register:$_networkKey:$_nonce:mallory:$_domain',
      'nonce swapped (message disagrees with the nonce column)':
          'dana-register:$_networkKey:cafe0bad:$_userName:$_domain',
      'network_key swapped (message disagrees with the network_key column)':
          'dana-register:00000000:$_nonce:$_userName:$_domain',
      'prefix replaced':
          'dana-transfer:$_networkKey:$_nonce:$_userName:$_domain',
      'wrong separator count (fields joined by underscores)':
          'dana-register:$fieldsJoinedByUnderscores',
      'wrong separator count (extra trailing field)':
          'dana-register:$_networkKey:$_nonce:$_userName:$_domain:extra',
    };

    for (final entry in tampered.entries) {
      test('tampered: ${entry.key} => throws FormatException', () async {
        final error =
            await _captureError(_challengeClient(message: entry.value));
        expect(error, isA<FormatException>(),
            reason: 'tampered message must be rejected before signing');
        final text = error.toString();
        expect(text, contains('does not match the requested binding'));
        // The rejection names the message the client expected, so the log
        // carries the honest binding.
        expect(text, contains('Expected: ${_validMessage()}'));
      });
    }

    test('garbage message => throws FormatException', () async {
      final error =
          await _captureError(_challengeClient(message: 'not-a-challenge'));
      expect(error, isA<FormatException>());
      expect(
          error.toString(), contains('does not match the requested binding'));
    });

    test('absent message field => throws FormatException (model parse guard)',
        () async {
      final error = await _captureError(_challengeClient(message: null));
      expect(error, isA<FormatException>());
    });

    test('absent network_key field => throws FormatException before returning',
        () async {
      final error = await _captureError(_challengeClient(
        message: _validMessage(),
        networkKey: null,
      ));
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('missing network_key'));
    });

    test('absent nonce field => throws FormatException (model parse guard)',
        () async {
      // requestChallenge never rebuilds a message from a null nonce: the
      // sibling response model rejects the response outright.
      final error = await _captureError(_challengeClient(
        message: _validMessage(),
        nonce: null,
      ));
      expect(error, isA<FormatException>());
    });

    test('non-200 still raises ChallengeRejectedException unchanged', () async {
      final client = MockClient((request) async =>
          Response(jsonEncode({'message': 'slow down'}), 429));
      final error = await _captureError(client);
      expect(error, isA<ChallengeRejectedException>());
      expect((error as ChallengeRejectedException).status, 429);
    });
  });
}
