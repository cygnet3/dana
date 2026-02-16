import 'package:danawallet/models/btc_amount.dart';

extension BtcAmountExtension on BtcAmount {
  String displayBtc() {
    final padded = toString().padLeft(9, '0');
    final whole = padded.substring(0, padded.length - 8);
    final decimal = padded.substring(padded.length - 8);
    return '₿ $whole.${decimal.substring(0, 2)}'
        ' ${decimal.substring(2, 5)}'
        ' ${decimal.substring(5)}';
  }

  String displaySats() {
    return '$this sats';
  }
}
