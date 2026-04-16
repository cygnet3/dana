import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/outpoint.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';

sealed class RecordedTransaction {
  final int id;
  final String? note;
  final int? confirmationTimestamp;

  RecordedTransaction({
    required this.id,
    this.note,
    this.confirmationTimestamp,
  });

  String get txid;
  int? get confirmationHeight;
  String? get confirmationBlockhash;
}

final class RecordedTransactionIncoming extends RecordedTransaction {
  @override
  final String txid;
  final Amount amount;
  @override
  final int? confirmationHeight;
  @override
  final String? confirmationBlockhash;

  RecordedTransactionIncoming({
    required super.id,
    super.note,
    super.confirmationTimestamp,
    required this.txid,
    required this.amount,
    this.confirmationHeight,
    this.confirmationBlockhash,
  });
}

final class RecordedTransactionOutgoing extends RecordedTransaction {
  @override
  final String txid;
  final List<OutPoint> spentOutpoints;
  final List<Recipient> recipients;
  @override
  final int? confirmationHeight;
  @override
  final String? confirmationBlockhash;
  final Amount change;
  final Amount fee;

  RecordedTransactionOutgoing({
    required super.id,
    super.note,
    super.confirmationTimestamp,
    required this.txid,
    required this.spentOutpoints,
    required this.recipients,
    this.confirmationHeight,
    this.confirmationBlockhash,
    required this.change,
    required this.fee,
  });

  Amount totalOutgoing() {
    final sum = recipients.fold(
      BigInt.zero,
      (acc, r) => acc + r.amount.field0,
    );
    return Amount(field0: sum + fee.field0);
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('txid: $txid');
    buffer.writeln('recipients:');
    for (final r in recipients) {
      buffer.writeln('  ${r.paymentCode}: ${r.amount.field0} sat');
    }
    buffer.writeln('fee: ${fee.field0} sat');
    buffer.writeln('change: ${change.field0} sat');
    buffer.write('confirmation_height: ${confirmationHeight ?? 'unconfirmed'}');
    return buffer.toString();
  }
}

final class RecordedTransactionUnknownOutgoing extends RecordedTransaction {
  final Amount amount;
  @override
  final int confirmationHeight;
  @override
  final String? confirmationBlockhash;
  final List<OutPoint> spentOutpoints;

  @override
  String get txid => 'Unknown';

  RecordedTransactionUnknownOutgoing({
    required super.id,
    super.note,
    super.confirmationTimestamp,
    required this.amount,
    required this.confirmationHeight,
    this.confirmationBlockhash,
    required this.spentOutpoints,
  });
}
