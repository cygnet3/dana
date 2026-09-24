class NameServerRegisterRequest {
  final String id;
  final String userName;
  final String domain;
  final String spAddress;
  final String nonce;
  final String signature;

  const NameServerRegisterRequest({
    required this.id,
    required this.userName,
    required this.domain,
    required this.spAddress,
    required this.nonce,
    required this.signature,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_name': userName,
      'domain': domain,
      'sp_address': spAddress,
      'nonce': nonce,
      'signature': signature,
    };
  }

  factory NameServerRegisterRequest.fromJson(Map<String, dynamic> json) {
    // Tolerant parse: nonce/signature are client-sent fields the server
    // never echoes back; fromJson exists for tests, so default them empty.
    return NameServerRegisterRequest(
      id: json['id'] as String,
      userName: json['user_name'] as String,
      domain: json['domain'] as String,
      spAddress: json['sp_address'] as String,
      nonce: json['nonce'] as String? ?? '',
      signature: json['signature'] as String? ?? '',
    );
  }
}
