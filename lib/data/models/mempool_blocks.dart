class MempoolGetBlockResponse {
  final String id;
  final int height;
  final int version;
  final int timestamp;
  final int txCount;
  final int size;
  final int weight;
  final String merkleRoot;
  final String previousblockhash;
  final int mediantime;
  final int nonce;
  final int bits;
  final double difficulty;

  const MempoolGetBlockResponse({
    required this.id,
    required this.height,
    required this.version,
    required this.timestamp,
    required this.txCount,
    required this.size,
    required this.weight,
    required this.merkleRoot,
    required this.previousblockhash,
    required this.mediantime,
    required this.nonce,
    required this.bits,
    required this.difficulty,
  });

  factory MempoolGetBlockResponse.fromJson(Map<String, dynamic> json) {
    return MempoolGetBlockResponse(
      id: json['id'] as String,
      height: json['height'] as int,
      version: json['version'] as int,
      timestamp: json['timestamp'] as int,
      txCount: json['tx_count'] as int,
      size: json['size'] as int,
      weight: json['weight'] as int,
      merkleRoot: json['merkle_root'] as String,
      previousblockhash: json['previousblockhash'] as String,
      mediantime: json['mediantime'] as int,
      nonce: json['nonce'] as int,
      bits: json['bits'] as int,
      difficulty: (json['difficulty'] as num).toDouble(),
    );
  }
}
