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

    final rawExpiresAt = json['expires_at'];
    final int? expiresAt = rawExpiresAt is num
        ? rawExpiresAt.toInt()
        : rawExpiresAt is String
            ? int.tryParse(rawExpiresAt)
            : null;

    return NameServerChallengeResponse(
      id: json['id'] as String?,
      message: message,
      nonce: nonce,
      networkKey: json['network_key'] as String?,
      expiresAt: expiresAt,
    );
  }
}
