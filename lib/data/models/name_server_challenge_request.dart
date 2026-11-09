/// Outbound-only request body for POST /challenge.
///
/// Deliberately has no `fromJson`: the server never echoes this shape back,
/// so a parse path here would be dead code (finding t_03cb4b3b, YAGNI).
/// The response direction is modelled by [NameServerChallengeResponse],
/// which validates with typed FormatExceptions.
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
}
