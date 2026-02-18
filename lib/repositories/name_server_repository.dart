import 'dart:convert';
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/name_server_info_response.dart';
import 'package:danawallet/data/models/name_server_lookup_response.dart';
import 'package:danawallet/data/models/name_server_register_request.dart';
import 'package:danawallet/data/models/name_server_register_response.dart';
import 'package:danawallet/data/models/prefix_search_response.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class NameServerRepository {
  String baseUrl;

  NameServerRepository({required ApiNetwork network})
      : baseUrl = (() {
          // live flavors only allow mainnet, so we don't need to separate based on the network
          if (appFlavor == 'live') {
            return nameServerLive;
          } else {
            // non-live flavors can have different networks
            if (network == ApiNetwork.mainnet) {
              // used for mainnet
              return nameServerDevMainnet;
            } else {
              // used for testnet/signet
              return nameServerDevTestnet;
            }
          }
        })();

  Future<NameServerInfoResponse> getInfo() async {
    Logger().d("Getting name server info");

    final response = await http.Client().get(
      Uri.parse('$baseUrl/info'),
    );

    Logger().d('Info response body: ${response.body}');
    if (response.statusCode == 200) {
      return NameServerInfoResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception("Received error with code ${response.statusCode}");
    }
  }

  /// Creates a dana address by calling the external name_server
  ///
  /// [danaAddress] - The address to register.
  /// [requestId] - The unique id for this request, can be useful for tracking requests.
  ///
  /// Returns [NameServerRegisterResponse] with the created address or error details
  Future<Bip353Address> registerDanaAddress({
    required Bip353Address danaAddress,
    required String paymentCode,
    required String requestId,
  }) async {
    final request = NameServerRegisterRequest(
      id: requestId,
      userName: danaAddress.username,
      domain: danaAddress.domain,
      spAddress: paymentCode,
    );

    Logger().d(
        'Registering dana address: $danaAddress with request ID: $requestId');
    final response = await http.Client().post(
      Uri.parse('$baseUrl/register'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(request.toJson()),
    );

    Logger().d('Registration response status: ${response.statusCode}');
    Logger().d('Registration response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      // Parse the server response
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final responseData = NameServerRegisterResponse.fromJson(decoded);

      // Validate that we got the expected fields
      if (responseData.danaAddress == null || responseData.spAddress == null) {
        throw Exception(
            'Server returned success but missing required fields. Response: ${response.body}');
      } else {
        Logger().i(
            'Successfully registered dana address: ${responseData.danaAddress}');
        return responseData.danaAddress!;
      }
    } else {
      // Server returned an error status
      Logger().e(
          'Registration failed with HTTP ${response.statusCode} ${response.reasonPhrase ?? "Unknown"}');
      Logger().e('Request URL: $baseUrl/register');
      Logger().e('Response body: ${response.body}');

      // todo: throw custom error types based on status code
      throw Exception(response.body);
    }
  }

  /// Looks up dana addresses associated with a silent payment address
  ///
  /// [spAddress] - The Silent Payment address to lookup
  ///
  /// Returns a list of dana addresses in the format `user_name@danawallet.app`
  /// Returns an empty list if no addresses are found
  /// Throws an exception for network errors, invalid responses, or malformed data
  Future<List<Bip353Address>> lookupDanaAddresses(
      String spAddress, String requestId) async {
    if (spAddress.isEmpty) {
      throw ArgumentError("Silent payment address cannot be empty");
    }
    Logger().d(
        'Looking up dana addresses for SP address: ${spAddress.substring(0, 20)}... (request ID: $requestId)');
    final response = await http.Client().get(
      Uri.parse('$baseUrl/lookup').replace(queryParameters: {
        'sp_address': spAddress,
        'id': requestId,
      }),
    );

    Logger().d('Lookup response status: ${response.statusCode}');
    Logger().d('Lookup response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final parsed =
          NameServerLookupResponse.fromJson(jsonDecode(response.body));
      return parsed.danaAddresses;
    } else if (response.statusCode == 404) {
      // a 404 status code means that this sp address has no associated dana addresses
      // we still parse the response struct to avoid a generic 404 error
      final parsed =
          NameServerLookupResponse.fromJson(jsonDecode(response.body));

      if (parsed.danaAddresses.isEmpty) {
        return parsed.danaAddresses;
      } else {
        throw Exception("Unexpected lack of dana addresses for 404");
      }
    } else {
      // unexpected status codes
      Logger().e("status code error: ${response.statusCode}");
      Logger().e("Body: ${response.body}");
      throw Exception("Lookup failure: ${response.body}");
    }
  }

  Future<PrefixSearchResponse> searchDanaAddressesWithPrefix(
      String prefix, String requestId) async {
    Logger().d(
        'Searching for dana addresses with prefix: $prefix (request ID: $requestId)');
    final response = await http.Client().get(
      Uri.parse('$baseUrl/search').replace(queryParameters: {
        'prefix': prefix,
        'id': requestId,
      }),
    );

    Logger().d('Prefix search response status: ${response.statusCode}');
    Logger().d('Prefix search response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final responseData = PrefixSearchResponse.fromJson(decoded);

        Logger().i(
            'Found ${responseData.count} dana address(es) matching prefix "$prefix" (total: ${responseData.totalCount})');
        return responseData;
      } catch (e, stackTrace) {
        Logger().e(
            'Failed to parse prefix search response (${response.statusCode}): $e');
        Logger().e('Response body: ${response.body}');
        Logger().e('Stack trace: $stackTrace');
        throw FormatException('Failed to parse prefix search response: $e');
      }
    } else if (response.statusCode == 404) {
      // No addresses found - return empty response
      Logger().d('No dana addresses found for prefix "$prefix" (404)');
      return PrefixSearchResponse(
        id: requestId,
        message: 'No addresses found',
        danaAddresses: [],
        count: 0,
        totalCount: 0,
      );
    } else {
      // Server returned an error status
      Logger().e(
          'Prefix search failed with HTTP ${response.statusCode} ${response.reasonPhrase ?? "Unknown"}');
      Logger().e('Request URL: $baseUrl/search');
      Logger().e('Response body: ${response.body}');

      // Try to parse as JSON error response
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final responseData = PrefixSearchResponse.fromJson(decoded);

        // If we got a valid error response with a message, use it
        if (responseData.message.isNotEmpty) {
          Logger().e('Server error message: ${responseData.message}');
          return responseData;
        } else {
          // Parsed but no message - create our own
          throw Exception(
              'Prefix search failed: HTTP ${response.statusCode}: ${response.reasonPhrase ?? "Unknown error"}');
        }
      } catch (parseError) {
        // Failed to parse error response
        String errorMessage;
        if (response.statusCode >= 500) {
          errorMessage =
              'Server error (${response.statusCode}): ${response.reasonPhrase ?? "Internal server error"}';
        } else if (response.statusCode == 400) {
          errorMessage = 'Bad request (400): Invalid prefix';
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          errorMessage =
              'Authentication error (${response.statusCode}): Unauthorized';
        } else {
          errorMessage =
              'HTTP ${response.statusCode}: ${response.reasonPhrase ?? "Unknown error"}';
        }
        throw Exception('Prefix search failed: $errorMessage');
      }
    }
  }
}
