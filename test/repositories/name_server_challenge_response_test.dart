import 'package:danawallet/data/models/name_server_challenge_response.dart';
import 'package:danawallet/repositories/name_server_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Table-driven coverage for the server->client wire models that ship with
/// zero Dart test references while the Rust half has its own unit tests
/// (finding t_f1bf6a52).
///
/// The heart of this suite is the `expires_at` anti-replay guard: it must
/// distinguish 'server omitted the field' (null, legal) from 'server sent a
/// garbage value' (typed FormatException), because a consumer gating on
/// `expiresAt != null` that sees a silent null on garbage fails OPEN.
///
/// Deliberately does not import lib/generated/** — pure Dart model tests
/// must run in a fresh worktree where the FRB bindings are absent.
void main() {
  const message = 'dana-register:9f2c7a4e:deadbeef:alice:danawallet.app';
  const nonce = 'deadbeef';

  Map<String, dynamic> validJson({Object? expiresAt = _absent}) {
    return <String, dynamic>{
      'id': 'req-1',
      'message': message,
      'nonce': nonce,
      'network_key': '9f2c7a4e',
      if (expiresAt != _absent) 'expires_at': expiresAt,
    };
  }

  /// Asserts [body] throws a FormatException whose message carries every
  /// needle — the same capture idiom as the sibling binding tests.
  void expectFormatException(
    void Function() body,
    List<String> needles,
  ) {
    Object? error;
    try {
      body();
    } catch (e) {
      error = e;
    }
    expect(error, isA<FormatException>(),
        reason: 'expected a FormatException, got: $error');
    final text = error.toString();
    for (final needle in needles) {
      expect(text, contains(needle));
    }
  }

  group('NameServerChallengeResponse.fromJson — happy path', () {
    test('all-fields parses every wire key', () {
      final r = NameServerChallengeResponse.fromJson(validJson(
        expiresAt: 1762100000,
      ));
      expect(r.id, 'req-1');
      expect(r.message, message);
      expect(r.nonce, nonce);
      expect(r.networkKey, '9f2c7a4e');
      expect(r.expiresAt, 1762100000);
    });

    test('numeric string expires_at parses to int', () {
      final r = NameServerChallengeResponse.fromJson(validJson(
        expiresAt: '1762100000',
      ));
      expect(r.expiresAt, 1762100000);
    });

    test('JSON number (double-integral) expires_at parses to int', () {
      final r = NameServerChallengeResponse.fromJson(validJson(
        expiresAt: 1762100000.0,
      ));
      expect(r.expiresAt, 1762100000);
      expect(r.expiresAt, isA<int>());
    });

    test('missing optional fields (id, network_key, expires_at) => nulls', () {
      final r = NameServerChallengeResponse.fromJson(<String, dynamic>{
        'message': message,
        'nonce': nonce,
      });
      expect(r.id, isNull);
      expect(r.networkKey, isNull);
      expect(r.expiresAt, isNull);
    });

    test('explicit JSON null for expires_at is the legal "no expiry" value',
        () {
      final r = NameServerChallengeResponse.fromJson(validJson(
        expiresAt: null,
      ));
      expect(r.expiresAt, isNull);
    });

    test('zero expires_at is a real value, not confused with absent', () {
      final r = NameServerChallengeResponse.fromJson(validJson(
        expiresAt: 0,
      ));
      expect(r.expiresAt, 0);
    });
  });

  group('NameServerChallengeResponse.fromJson — missing required fields', () {
    test('missing message throws FormatException naming the field', () {
      expectFormatException(
        () => NameServerChallengeResponse.fromJson(<String, dynamic>{
          'nonce': nonce,
        }),
        ['missing required field message'],
      );
    });

    test('missing nonce throws FormatException naming the field', () {
      expectFormatException(
        () => NameServerChallengeResponse.fromJson(<String, dynamic>{
          'message': message,
        }),
        ['missing required field nonce'],
      );
    });

    test('wrong-typed required fields are refused', () {
      expectFormatException(
        () => NameServerChallengeResponse.fromJson(<String, dynamic>{
          'message': 42,
          'nonce': nonce,
        }),
        ['missing required field message'],
      );
      expectFormatException(
        () => NameServerChallengeResponse.fromJson(<String, dynamic>{
          'message': message,
          'nonce': <String>['a'],
        }),
        ['missing required field nonce'],
      );
    });
  });

  group('NameServerChallengeResponse.fromJson — expires_at fail-closed', () {
    // The regression this suite exists for (finding t_f1bf6a52): every one of
    // these used to collapse to null, indistinguishable from an omitted field.
    final garbage = <String, Object?>{
      'bool': true,
      'list': <int>[1],
      'map': <String, int>{'a': 1},
      'string non-integer': 'soon',
      'string timestamp': '2026-10-03T00:08:35Z',
      'empty string': '',
      'whitespace string': ' ',
      'negative string': '-1',
      'negative int': -5,
      'NaN': double.nan,
      'infinity': double.infinity,
      'fractional': 1762100000.5,
    };

    garbage.forEach((label, value) {
      test('present-but-unparseable expires_at ($label) throws', () {
        expectFormatException(
          () => NameServerChallengeResponse.fromJson(validJson(
            expiresAt: value,
          )),
          ['expires_at', 'malformed'],
        );
      });
    });
  });

  group('RejectedException payloads', () {
    test('ChallengeRejectedException carries status/body and renders both', () {
      final e = ChallengeRejectedException(429, 'too many requests');
      expect(e.status, 429);
      expect(e.body, 'too many requests');
      expect(e.toString(), contains('429'));
      expect(e.toString(), contains('too many requests'));
    });

    test('RegisterRejectedException carries status/message and renders both',
        () {
      final e = RegisterRejectedException(401, 'bad nonce');
      expect(e.status, 401);
      expect(e.message, 'bad nonce');
      expect(e.toString(), contains('401'));
      expect(e.toString(), contains('bad nonce'));
    });
  });
}

/// Sentinel distinguishing 'key omitted' from 'key present with null'.
const Object _absent = Object();
