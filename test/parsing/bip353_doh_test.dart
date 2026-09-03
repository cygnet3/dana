import 'package:danawallet/exceptions.dart';
import 'package:danawallet/parsing/bip353_doh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('txtDataFromDohResponse', () {
    test('returns null on NXDOMAIN', () {
      expect(txtDataFromDohResponse({'Status': 3}), isNull);
    });

    test('returns null when NOERROR has no Answer', () {
      expect(txtDataFromDohResponse({'Status': 0}), isNull);
    });

    test('returns null on an empty Answer list', () {
      expect(txtDataFromDohResponse({'Status': 0, 'Answer': []}), isNull);
    });

    test('returns null when the answer has no TXT record', () {
      expect(
        txtDataFromDohResponse({
          'Status': 0,
          'Answer': [
            {'type': 5, 'data': 'alias.example.com.'},
          ],
        }),
        isNull,
      );
    });

    test('returns the decoded URI on NOERROR with a single TXT record', () {
      expect(
        txtDataFromDohResponse({
          'Status': 0,
          'Answer': [
            {'type': dohTypeTxt, 'data': '"bitcoin:?sp=sp1qexample"'},
          ],
        }),
        'bitcoin:?sp=sp1qexample',
      );
    });

    test(
        'returns a bitcoin: record that is not a valid URI; '
        'validity is for the BIP-321 parser to decide', () {
      expect(
        txtDataFromDohResponse({
          'Status': 0,
          'Answer': [
            {'type': dohTypeTxt, 'data': '"bitcoin:not a valid uri"'},
          ],
        }),
        'bitcoin:not a valid uri',
      );
    });

    test('throws Bip353DnsStatusException on SERVFAIL', () {
      expect(
        () => txtDataFromDohResponse({'Status': 2}),
        throwsA(isA<Bip353DnsStatusException>()
            .having((e) => e.status, 'status', 2)),
      );
    });

    test('throws Bip353TransportException when Status is missing', () {
      expect(
        () => txtDataFromDohResponse({'Answer': []}),
        throwsA(isA<Bip353TransportException>()),
      );
    });

    test('throws Bip353TransportException when Status is not an int', () {
      expect(
        () => txtDataFromDohResponse({'Status': '0', 'Answer': []}),
        throwsA(isA<Bip353TransportException>()),
      );
    });

    test('throws Bip353TransportException when Answer is not a list', () {
      expect(
        () => txtDataFromDohResponse({'Status': 0, 'Answer': 'oops'}),
        throwsA(isA<Bip353TransportException>()),
      );
    });

    test('throws Bip353InvalidRecordException on multiple bitcoin: TXT records',
        () {
      expect(
        () => txtDataFromDohResponse({
          'Status': 0,
          'Answer': [
            {'type': dohTypeTxt, 'data': '"bitcoin:?sp=one"'},
            {'type': dohTypeTxt, 'data': '"bitcoin:?sp=two"'},
          ],
        }),
        throwsA(isA<Bip353InvalidRecordException>()),
      );
    });

    test('returns the bitcoin: URI when a non-bitcoin TXT is also present', () {
      expect(
        txtDataFromDohResponse({
          'Status': 0,
          'Answer': [
            {'type': dohTypeTxt, 'data': '"v=spf1 -all"'},
            {'type': dohTypeTxt, 'data': '"bitcoin:?sp=sp1qexample"'},
          ],
        }),
        'bitcoin:?sp=sp1qexample',
      );
    });
  });

  group('singleTxtDataFromDohAnswers', () {
    test('returns null for an empty answer list', () {
      expect(singleTxtDataFromDohAnswers([]), isNull);
    });

    test('returns null when only CNAME records are present', () {
      final answers = [
        {
          'name': 'alice.user._bitcoin-payment.dana.me.',
          'type': 5,
          'data': 'alias.example.com.',
        },
      ];

      expect(singleTxtDataFromDohAnswers(answers), isNull);
    });

    test('returns the decoded URI when a CNAME precedes a single TXT', () {
      final answers = [
        {
          'name': 'alice.user._bitcoin-payment.dana.me.',
          'type': 5,
          'data': 'alias.example.com.',
        },
        {
          'name': 'alice.user._bitcoin-payment.dana.me.',
          'type': dohTypeTxt,
          'data': '"bitcoin:?sp=sp1qexample&amount=0.001"',
        },
      ];

      expect(
          singleTxtDataFromDohAnswers(answers), 'bitcoin:?sp=sp1qexample&amount=0.001');
    });

    test('throws when more than one bitcoin: TXT record is present', () {
      final answers = [
        {'type': dohTypeTxt, 'data': '"bitcoin:?sp=one"'},
        {'type': dohTypeTxt, 'data': '"bitcoin:?sp=two"'},
      ];

      expect(
        () => singleTxtDataFromDohAnswers(answers),
        throwsA(isA<Bip353InvalidRecordException>().having(
          (e) => e.message,
          'message',
          'Multiple bitcoin: TXT records found; expected at most one',
        )),
      );
    });

    test('throws on ambiguity even when one claimant is malformed', () {
      final answers = [
        {'type': dohTypeTxt, 'data': '"bitcoin:?sp=one"'},
        {'type': dohTypeTxt, 'data': r'"bitcoin:?x=foo\nbar"'},
      ];

      expect(
        () => singleTxtDataFromDohAnswers(answers),
        throwsA(isA<Bip353InvalidRecordException>()),
      );
    });

    test('treats a malformed bitcoin: record as a claimant', () {
      final answers = [
        {'type': dohTypeTxt, 'data': r'"bitcoin:?x=foo\nbar"'},
      ];

      expect(singleTxtDataFromDohAnswers(answers), r'bitcoin:?x=foo\nbar');
    });

    test('ignores non-bitcoin TXT records', () {
      final answers = [
        {'type': dohTypeTxt, 'data': '"v=spf1 include:_spf.example.com ~all"'},
        {'type': dohTypeTxt, 'data': '"bitcoin:?sp=sp1qexample"'},
      ];

      expect(singleTxtDataFromDohAnswers(answers), 'bitcoin:?sp=sp1qexample');
    });

    test('returns null when only non-bitcoin TXT records are present', () {
      expect(
        singleTxtDataFromDohAnswers([
          {'type': dohTypeTxt, 'data': '"v=spf1 -all"'},
        ]),
        isNull,
      );
    });

    test('ignores non-map entries in the answer list', () {
      final answers = [
        'not a record',
        16,
        {'type': dohTypeTxt, 'data': '"bitcoin:?sp=sp1qexample"'},
      ];

      expect(singleTxtDataFromDohAnswers(answers), 'bitcoin:?sp=sp1qexample');
    });

    test('ignores TXT records with missing data', () {
      expect(
        singleTxtDataFromDohAnswers([
          {'type': dohTypeTxt},
        ]),
        isNull,
      );
    });
  });

  group('bitcoinUriFromDnsTxt', () {
    test('unwraps a quoted bitcoin URI', () {
      expect(
        bitcoinUriFromDnsTxt('"bitcoin:?sp=sp1qexample&amount=0.001"'),
        'bitcoin:?sp=sp1qexample&amount=0.001',
      );
    });

    test('accepts an unquoted bitcoin URI', () {
      expect(
        bitcoinUriFromDnsTxt('  bitcoin:?sp=sp1qexample&amount=0.001  '),
        'bitcoin:?sp=sp1qexample&amount=0.001',
      );
    });

    test('concatenates RFC 1035 character-strings without inserting a space',
        () {
      expect(
        bitcoinUriFromDnsTxt('"bitcoin:?" "sp=sp1qexample&amount=0.001"'),
        'bitcoin:?sp=sp1qexample&amount=0.001',
      );
    });

    test('unescapes quoted quotes and backslashes', () {
      expect(
        bitcoinUriFromDnsTxt(r'"bitcoin:?message=hello \"world\" path=a\\b"'),
        'bitcoin:?message=hello "world" path=a\\b',
      );
    });

    test('accepts an uppercase BITCOIN: prefix', () {
      expect(
        bitcoinUriFromDnsTxt('"BITCOIN:?sp=sp1qexample"'),
        'BITCOIN:?sp=sp1qexample',
      );
    });

    test('percent-decodes the TXT value', () {
      expect(
        bitcoinUriFromDnsTxt('"bitcoin:?sp=sp1qexample%26amount=0.001"'),
        'bitcoin:?sp=sp1qexample&amount=0.001',
      );
    });

    test('returns null when the record is not a bitcoin URI', () {
      expect(bitcoinUriFromDnsTxt('"https://example.com"'), isNull);
    });

    test('keeps an unsupported DNS TXT escape verbatim', () {
      expect(
        bitcoinUriFromDnsTxt(r'"bitcoin:?x=foo\nbar"'),
        r'bitcoin:?x=foo\nbar',
      );
    });

    test('keeps an octal DNS TXT escape verbatim', () {
      expect(
        bitcoinUriFromDnsTxt(r'"bitcoin:?x=\040"'),
        r'bitcoin:?x=\040',
      );
    });

    test('keeps a trailing backslash verbatim', () {
      expect(
        bitcoinUriFromDnsTxt(r'bitcoin:?x=abc\'),
        r'bitcoin:?x=abc\',
      );
    });

    test('strips a stray quote when the quote is unclosed', () {
      expect(
        bitcoinUriFromDnsTxt('"bitcoin:?sp=sp1qexample'),
        'bitcoin:?sp=sp1qexample',
      );
    });

    test('falls back to the raw value on invalid percent-encoding', () {
      expect(
        bitcoinUriFromDnsTxt('"bitcoin:?x=100%"'),
        'bitcoin:?x=100%',
      );
    });

    test('concatenates quoted chunks even when garbage sits between them', () {
      expect(bitcoinUriFromDnsTxt('"foo" garbage "bar"'), isNull);
      expect(
        bitcoinUriFromDnsTxt('"bitcoin:?" garbage "sp=sp1qexample"'),
        'bitcoin:?sp=sp1qexample',
      );
    });
  });
}
