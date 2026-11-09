class NameServerChallengeResponse {
  final String? id;
  final String message;
  final String nonce;
  final String? networkKey;
  final int? expiresAt;

  const NameServerChallengeResponse({
    this.id,
    required this.message,
    required this.nonce,
    this.networkKey,
    this.expiresAt,
  });

  factory NameServerChallengeResponse.fromJson(Map<String, dynamic> json) {
    final message = json['message'];
    if (message is! String) {
      throw const FormatException(
        'NameServerChallengeResponse.fromJson: missing required field message',
      );
    }
    final nonce = json['nonce'];
    if (nonce is! String) {
      throw const FormatException(
        'NameServerChallengeResponse.fromJson: missing required field nonce',
      );
    }

    // expires_at is the anti-replay guard the client gates on (the server
    // issues nonces with NONCE_TTL_SECS=300), so the three input classes
    // must stay distinguishable: an ABSENT (or explicitly null) field is a
    // legal server choice and yields null; a PRESENT but unparseable value
    // is a wire-format violation and throws rather than collapsing to the
    // same null a missing field produces (finding t_f1bf6a52).
    final int? expiresAt = _parseExpiresAt(
      json['expires_at'],
      present: json.containsKey('expires_at'),
    );

    return NameServerChallengeResponse(
      id: json['id'] as String?,
      message: message,
      nonce: nonce,
      networkKey: json['network_key'] as String?,
      expiresAt: expiresAt,
    );
  }
}

/// Shared by [NameServerChallengeResponse.fromJson]: validates the optional
/// `expires_at` epoch-seconds field without collapsing garbage into the
/// `null` that an absent field legitimately produces.
///
/// - absent (key missing, or present with an explicit JSON null) -> null;
/// - `num` that is NaN/Infinity, fractional, or negative -> FormatException;
/// - `String` that does not parse as an integer, or parses negative -> FormatException;
/// - any other runtime type -> FormatException naming the field.
int? _parseExpiresAt(dynamic raw, {required bool present}) {
  if (!present || raw == null) {
    return null;
  }
  if (raw is num) {
    if (raw.isNaN || raw.isInfinite || raw < 0 || raw != raw.toInt()) {
      throw FormatException(
        'NameServerChallengeResponse.fromJson: malformed expires_at: $raw',
      );
    }
    return raw.toInt();
  }
  if (raw is String) {
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) {
      throw FormatException(
        'NameServerChallengeResponse.fromJson: malformed expires_at: "$raw"',
      );
    }
    return parsed;
  }
  throw FormatException(
    'NameServerChallengeResponse.fromJson: malformed expires_at: '
    'unexpected type ${raw.runtimeType}',
  );
}
