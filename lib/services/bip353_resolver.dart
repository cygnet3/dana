import 'dart:convert';

import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:dart_bip353/dart_bip353.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
// ignore: implementation_imports
import 'package:dart_bip353/src/response_model.dart';

class Bip353Resolver {
  static Future<bool> isBip353AddressPresent(
      Bip353Address address, Network network) async {
    try {
      final paymentCode = await resolve(address, network);
      // If null or no silent payment, address is available
      return paymentCode == null;
    } catch (e) {
      // If we can't resolve due to network error, assume it's taken to be safe
      Logger().e('Error checking address availability: $e');
      return false;
    }
  }

  /// Resolves a dana address to its payment information via DNS
  ///
  /// Returns [String] if the address exists and is valid
  /// Returns null if the DNS record doesn't exist (address not registered)
  /// Throws an exception for network errors, invalid responses, or malformed data
  static Future<String?> resolve(Bip353Address address, Network network) async {
    if (network == Network.regtest) {
      throw Exception("regtest not allowed");
    }

    final query = Bip353.buildDnsQuery(address.username, address.domain);
    final url = "${Bip353.dnsResolver}?name=$query&type=TXT";

    try {
      final response = await http.Client().get(
        Uri.parse(url),
        headers: {"Accept": "application/dns-json"},
      );

      Logger().d('DNS response: ${response.body}');

      // Check HTTP status code
      if (response.statusCode != 200) {
        throw Exception(
            'DNS query failed with status ${response.statusCode}: ${response.body}');
      }

      // Parse JSON response
      final Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw FormatException('Invalid JSON response from DNS server: $e');
      }

      // Check DNS response status
      // Status 0 = NOERROR (success)
      // Status 3 = NXDOMAIN (domain doesn't exist)
      final status = decoded["Status"] as int?;

      if (status == 3 || (status == 0 && decoded["Answer"] == null)) {
        // DNS record doesn't exist - this is not an error, just means address not registered
        return null;
      }

      if (status != 0) {
        throw Exception('DNS query returned error status: $status');
      }

      final answer = decoded["Answer"] as List<dynamic>?;
      if (answer == null || answer.isEmpty) {
        return null;
      }

      final firstRecord = answer.first as Map<String, dynamic>;
      final data = firstRecord["data"] as String;

      final parsed = Bip353DnsResolveResponse.fromRawQueryData(data);
      if (network == Network.mainnet && parsed.silentpayment != null) {
        return parsed.silentpayment;
      } else if ((network == Network.testnet3 ||
              network == Network.testnet4 ||
              network == Network.signet) &&
          parsed.testsilentpayment != null) {
        return parsed.testsilentpayment;
      } else {
        // if we have a dns entry but no silent payment record, throw an error
        throw Exception("Record exists, but no silent payment entry");
      }
    } on FormatException {
      rethrow;
    } on ArgumentError {
      rethrow;
    } catch (e) {
      // Network errors, timeouts, etc.
      throw Exception('Failed to resolve address $address: $e');
    }
  }

  static Future<bool> verifyPaymentCode(
      Bip353Address danaAddress, String paymentCode, Network network) async {
    Logger().i("dana address to verify: $danaAddress");

    final resolved = await resolve(danaAddress, network);
    Logger().i("resolved address from dana address: $resolved");

    return resolved == paymentCode;
  }
}
