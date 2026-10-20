import 'package:danawallet/generated/rust/api/structs/bip321_uri.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/exceptions.dart';
import 'package:danawallet/generated/rust/api/structs/silent_payment_code.dart';

extension Bip321UriExtension on Bip321Uri {
  SilentPaymentCode? reusablePaymentCodeForNetwork(Network network) {
    switch (network) {
      case Network.mainnet:
        if (sp.isNotEmpty) {
          if (sp.length > 1) {
            throw AmbiguousPaymentUriException();
          }
          return SilentPaymentCode.parse(code: sp.first);
        } else {
          return null;
        }
      default:
        if (tsp.isNotEmpty) {
          if (tsp.length > 1) {
            throw AmbiguousPaymentUriException();
          }
          return SilentPaymentCode.parse(code: tsp.first);
        } else {
          return null;
        }
    }
  }

  String? legacyPaymentCodeForNetwork(Network network) {
    switch (network) {
      case Network.mainnet:
        if (bc.isNotEmpty) {
          return bc.first;
        }
        return address;
      default:
        if (tb.isNotEmpty) {
          return tb.first;
        }
        return null;
    }
  }
}
