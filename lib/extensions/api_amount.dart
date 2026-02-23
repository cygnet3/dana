import 'package:danawallet/constants.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';

extension ApiAmountExtension on ApiAmount {
  ApiAmount operator +(ApiAmount other) {
    return ApiAmount(field0: field0 + other.field0);
  }

  String displayBtc() {
    final btcPart = field0 ~/ BigInt.from(bitcoinUnits);
    final satsPart = (field0 % BigInt.from(bitcoinUnits));
    final satsStr = satsPart.toString().padLeft(8, '0');
    return '₿ $btcPart.${satsStr.substring(0, 2)} ${satsStr.substring(2, 5)} ${satsStr.substring(5, 8)}';
  }

  String displaySats() {
    return '$field0 sats';
  }
}
