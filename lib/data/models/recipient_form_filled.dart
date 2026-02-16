import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/models/btc_amount.dart';

class RecipientFormFilled {
  Contact recipient;
  BtcAmount amount;
  int feerate;

  RecipientFormFilled(
      {required this.recipient, required this.amount, required this.feerate});
}
