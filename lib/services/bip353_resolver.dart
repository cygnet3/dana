import 'dart:convert';

import 'package:danawallet/constants.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/exceptions.dart';
import 'package:danawallet/generated/rust/api/bip321.dart';
import 'package:danawallet/generated/rust/api/structs/bip321_uri.dart';
import 'package:danawallet/parsing/bip353_doh.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class Bip353Resolver {
  /// Resolves a dana address via DNS and parses the stored payment URI in Rust.
  ///
  /// Returns a parsed Bip321Uri.
  /// Throws [Bip353TransportException] if the DoH request fails,
  /// [Bip353AddressNotRegisteredException] if no TXT record at the name claims
  /// to be a payment instruction (NXDOMAIN, NODATA, or only non-`bitcoin:` TXT),
  /// [Bip353DnsStatusException] if the resolver returns an error status, and
  /// [Bip353InvalidRecordException] if a `bitcoin:` record cannot be parsed as
  /// a payment URI or multiple `bitcoin:` records are present.
  static Future<Bip321Uri> resolveParsed(Bip353Address address) async {
    final url = '$dnsOverHttpsEndpoint?name=${address.dnsQuery}&type=TXT';

    final http.Response response;
    try {
      response = await http.Client().get(
        Uri.parse(url),
        headers: {"Accept": "application/dns-json"},
      );
    } catch (e) {
      throw Bip353TransportException('DNS query failed for $address', cause: e);
    }

    Logger().d('DNS response: ${response.body}');

    if (response.statusCode != 200) {
      throw Bip353TransportException(
          'DNS query failed with status ${response.statusCode}: ${response.body}');
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw Bip353TransportException('Invalid JSON response from DNS server',
          cause: e);
    }

    final uri = txtDataFromDohResponse(decoded);
    if (uri == null) {
      throw Bip353AddressNotRegisteredException(address);
    }

    try {
      return parsePaymentUri(uri: uri);
    } catch (e) {
      throw Bip353InvalidRecordException(
          'Invalid payment URI in DNS record for $address',
          cause: e);
    }
  }
}
