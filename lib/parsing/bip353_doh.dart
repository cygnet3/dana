import 'package:danawallet/exceptions.dart';

/// RFC 1035 TXT. DoH JSON uses this integer in `Answer[].type`.
const int dohTypeTxt = 16;

/// Interprets a decoded `application/dns-json` response for a BIP-353 TXT
/// query. Returns the decoded `bitcoin:` URI from the single TXT RR claiming
/// to be one, or null when the name has no payment instruction (NXDOMAIN,
/// empty answer, or no `bitcoin:` TXT).
///
/// Throws [Bip353TransportException] on a malformed response,
/// [Bip353DnsStatusException] on a resolver error status, and
/// [Bip353InvalidRecordException] when more than one `bitcoin:` TXT RR is
/// present.
String? txtDataFromDohResponse(Map<String, dynamic> decoded) {
  final status = decoded["Status"];
  if (status is! int) {
    throw const Bip353TransportException(
        'Malformed DNS response: missing or invalid Status field');
  }

  if (status == 3 || (status == 0 && decoded["Answer"] == null)) {
    return null;
  }

  if (status != 0) {
    throw Bip353DnsStatusException('DNS query returned error status $status',
        status: status);
  }

  final answer = decoded["Answer"];
  if (answer is! List) {
    throw const Bip353TransportException(
        'Malformed DNS response: Answer field is not a list');
  }
  if (answer.isEmpty) {
    return null;
  }

  return singleTxtDataFromDohAnswers(answer);
}

/// Returns the decoded `bitcoin:` URI of the single BIP-353 TXT RR, or null
/// if none of the answers claims to be a payment instruction.
///
/// Non-TXT answers and TXT RRs that do not decode to a `bitcoin:` URI are
/// ignored (BIP-353). Throws [Bip353InvalidRecordException] if more than one
/// TXT RR claims to be a `bitcoin:` URI, even a malformed one: ambiguity is
/// never resolved by guessing.
String? singleTxtDataFromDohAnswers(List<dynamic> answers) {
  final bitcoinUris = <String>[];

  for (final record in answers.whereType<Map<String, dynamic>>()) {
    if (record['type'] != dohTypeTxt) {
      continue;
    }
    final data = record['data'];
    if (data is! String) {
      continue;
    }

    final uri = bitcoinUriFromDnsTxt(data);
    if (uri != null) {
      bitcoinUris.add(uri);
    }
  }

  if (bitcoinUris.isEmpty) {
    return null;
  }
  if (bitcoinUris.length > 1) {
    throw const Bip353InvalidRecordException(
        'Multiple bitcoin: TXT records found; expected at most one');
  }
  return bitcoinUris.single;
}

/// Decodes a DoH JSON TXT `data` value and returns the `bitcoin:` URI it
/// claims to be, or null if it doesn't claim to be one.
///
/// "Claims" is deliberately shallow: only the prefix is checked. Whether the
/// URI is actually valid is for the BIP-321 parser to decide.
String? bitcoinUriFromDnsTxt(String data) {
  final uri = decodeDnsTxtPayload(data);

  if (!uri.toLowerCase().startsWith('bitcoin:')) {
    return null;
  }
  return uri;
}

/// Concatenates RFC 1035 `<character-string>`s in a DoH JSON TXT `data` field.
///
/// Lenient by design: this never throws. Resolver formatting varies, so
/// malformed input is decoded best-effort and left for the URI parser to
/// judge.
String decodeDnsTxtPayload(String data) {
  // DoH JSON returns TXT data as one or more quoted, backslash-escaped strings
  // separated by spaces (RFC 1035 §3.3.14). Extract and concatenate each chunk.
  final chunkRe = RegExp(r'"((?:[^"\\]|\\.)*)"');
  final matches = chunkRe.allMatches(data).toList();

  // Some resolvers omit surrounding quotes; fall back to the raw value,
  // stripping stray surrounding quotes if present.
  final raw = matches.isEmpty
      ? _stripStrayQuotes(data.trim())
      : matches.map((m) => _unescapeDnsTxtChunk(m.group(1)!)).join();

  // Some resolvers percent-encode the TXT value inside the JSON field. If the
  // encoding is invalid, keep the raw value for the URI parser to judge.
  try {
    return Uri.decodeComponent(raw);
  } on ArgumentError {
    return raw;
  }
}

/// Removes one stray leading and/or trailing quote from an unquoted TXT value.
String _stripStrayQuotes(String data) {
  var result = data;
  if (result.startsWith('"')) {
    result = result.substring(1);
  }
  if (result.endsWith('"') && result.isNotEmpty) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

/// Best-effort unescaping of a quoted chunk: `\"` and `\\` are unescaped,
/// anything else (unknown escapes, trailing backslash) is kept verbatim for
/// the URI parser to judge.
String _unescapeDnsTxtChunk(String chunk) {
  final buffer = StringBuffer();

  for (var i = 0; i < chunk.length; i++) {
    final char = chunk[i];
    if (char != r'\') {
      buffer.write(char);
      continue;
    }

    if (i + 1 >= chunk.length) {
      buffer.write(char);
      continue;
    }

    final escaped = chunk[++i];
    if (escaped == '"' || escaped == r'\') {
      buffer.write(escaped);
    } else {
      buffer.write(char);
      buffer.write(escaped);
    }
  }

  return buffer.toString();
}
