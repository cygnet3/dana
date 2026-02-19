/// Response from mempool.space `/v1/mining/blocks/timestamp/{timestamp}` API.
class MempoolBlockTimestampResponse {
  final int height;
  final String hash;
  final String timestamp;

  const MempoolBlockTimestampResponse({
    required this.height,
    required this.hash,
    required this.timestamp,
  });

  factory MempoolBlockTimestampResponse.fromJson(Map<String, dynamic> json) {
    return MempoolBlockTimestampResponse(
      height: json['height'] as int,
      hash: json['hash'] as String,
      timestamp: json['timestamp'] as String,
    );
  }
}
