import 'package:danawallet/constants.dart';

enum AmountDisplayUnit {
  btc,
  sats;

  String displayNameLabel() {
    switch (this) {
      case AmountDisplayUnit.btc:
        return 'Bitcoin ($btcSymbol)';
      case AmountDisplayUnit.sats:
        return 'Satoshis ($satSymbol)';
    }
  }
}
