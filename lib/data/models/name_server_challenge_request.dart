class NameServerChallengeRequest {
  final String id;
  final String userName;
  final String domain;
  final String spAddress;

  const NameServerChallengeRequest({
    required this.id,
    required this.userName,
    required this.domain,
    required this.spAddress,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_name': userName,
      'domain': domain,
      'sp_address': spAddress,
    };
  }

  factory NameServerChallengeRequest.fromJson(Map<String, dynamic> json) {
    return NameServerChallengeRequest(
      id: json['id'] as String,
      userName: json['user_name'] as String,
      domain: json['domain'] as String,
      spAddress: json['sp_address'] as String,
    );
  }
}
