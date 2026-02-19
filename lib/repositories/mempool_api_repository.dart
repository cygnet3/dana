import 'dart:convert';

import 'package:danawallet/data/models/mempool_block_timestamp_response.dart';
import 'package:danawallet/data/models/mempool_blocks.dart';
import 'package:danawallet/data/models/mempool_prices_response.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/services/fee_api_converter.dart';
import 'package:http/http.dart' as http;
import 'package:danawallet/data/models/recommended_fee_model.dart';
import 'package:danawallet/services/mempool_fee_api_converter.dart';
import 'package:logger/logger.dart';

class MempoolApiRepository {
  final String baseUrl;
  final FeeConverter converter;

  MempoolApiRepository({ApiNetwork network = ApiNetwork.mainnet})
      : baseUrl =
            'https://mempool.space/${network != ApiNetwork.mainnet ? '${network.name}/' : ''}api',
        converter = MempoolApiFeeConverter();

  Future<RecommendedFeeResponse> getCurrentFeeRate() async {
    final response = await http.get(Uri.parse('$baseUrl/v1/fees/recommended'));
    if (response.statusCode == 200) {
      try {
        return converter.convert(jsonDecode(response.body));
      } catch (e) {
        throw Exception('Failed to parse recommended fees response: $e');
      }
    } else {
      throw Exception(
          'Failed to get latest fee rates, response status: ${response.statusCode}');
    }
  }

  Future<MempoolPricesResponse> getExchangeRate() async {
    final response = await http.get(Uri.parse('$baseUrl/v1/prices'));
    if (response.statusCode == 200) {
      try {
        return MempoolPricesResponse.fromJson(jsonDecode(response.body));
      } catch (e) {
        throw Exception('Unexpected format: $e');
      }
    } else {
      throw Exception('Unexpected status code: ${response.statusCode}');
    }
  }

  Future<String> postTransaction(String finalizedTransactionHex) async {
    Logger().d("Broadcasting transaction using mempool.space api");
    final response = await http.post(Uri.parse('$baseUrl/tx'),
        body: finalizedTransactionHex);

    Logger().d("Broadcast response status code: ${response.statusCode}");
    Logger().d("Broadcast response body: ${response.body}");

    if (response.statusCode == 200) {
      // response is not json-encoded, so just read the body directly
      final txid = response.body;

      return txid;
    } else {
      throw Exception("Unexpected status code: ${response.statusCode}");
    }
  }

  Future<MempoolGetBlockResponse> getBlockForHash(String blockHash) async {
    final response = await http.get(Uri.parse('$baseUrl/block/$blockHash'));
    if (response.statusCode == 200) {
      return MempoolGetBlockResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Unexpected status code: ${response.statusCode}');
    }
  }

  Future<String> getBlockHashForHeight(int height) async {
    // First get the block hash from height
    final hashResponse = await http.get(Uri.parse('$baseUrl/block-height/$height'));
    if (hashResponse.statusCode != 200) {
      throw Exception('Unexpected status code: ${hashResponse.statusCode}');
    }
    
    // Then get the full block data using the hash
    return hashResponse.body.trim();
  }

  /// Converts a Unix timestamp to block info using mempool API.
  /// Returns the block closest to the given timestamp.
  Future<MempoolBlockTimestampResponse> getBlockFromTimestamp(int timestamp) async {
    final response = await http.get(
      Uri.parse('$baseUrl/v1/mining/blocks/timestamp/$timestamp'),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to get block from timestamp: ${response.statusCode}',
      );
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return MempoolBlockTimestampResponse.fromJson(json);
    } catch (e) {
      throw Exception('Failed to parse block timestamp response: $e');
    }
  }
}
