import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/data/models/recipient_form_filled.dart';
import 'package:danawallet/data/models/recommended_fee_model.dart';
import 'package:danawallet/data/enums/selected_fee.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/unsigned_transaction.dart';

// this singleton class contains all filled data during the send flow
// to save data in a global state, we use a singleton class.
// this is very similar to using Provider, but without NotifyListeners
class RecipientForm {
  Contact? recipient;
  ApiAmount? amount;
  SelectedFee? selectedFee;
  int? customFeeRate;
  RecommendedFeeResponse? currentFeeRates;
  ApiSilentPaymentUnsignedTransaction? unsignedTx;

  static final RecipientForm _instance = RecipientForm._internal();

  factory RecipientForm() {
    return _instance;
  }

  RecipientForm._internal();

  void reset() {
    _instance.recipient = null;
    _instance.amount = null;
    _instance.selectedFee = null;
    _instance.customFeeRate = null;
    _instance.unsignedTx = null;
    _instance.currentFeeRates = null;
  }

  RecipientFormFilled toFilled() {
    if (recipient == null ||
        amount == null ||
        selectedFee == null ||
        currentFeeRates == null) {
      throw Exception('Not all required parameters filled');
    }

    if (selectedFee == SelectedFee.custom && customFeeRate == null) {
      throw Exception('Custom fee rate should be set');
    }

    final feerate = selectedFee == SelectedFee.custom
        ? customFeeRate!
        : selectedFee!.getFeeRate(currentFeeRates!);

    return RecipientFormFilled(
        recipient: recipient!, amount: amount!, feerate: feerate);
  }
}
