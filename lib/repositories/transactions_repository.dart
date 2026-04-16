import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/data/models/recorded_transaction.dart';
import 'package:danawallet/generated/rust/api/legacy/history.dart';
import 'package:danawallet/generated/rust/api/legacy/recorded_transaction.dart'
    as frb_legacy;
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/outpoint.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class TransactionsRepository {
  // private constructor
  TransactionsRepository._();

  // singleton
  static final instance = TransactionsRepository._();

  Future<Database> get _db async => await DatabaseHelper.instance.database;

  Future<void> reset() async {
    final db = await _db;
    await db.delete('transactions');
    // note: can be removed after adding foreign_keys pragma
    await db.delete('tx_recipients');
    await db.delete('tx_spent_outpoints');
  }

  /// returns the sum of all owned outputs that were spent in this transaction
  /// for incoming transactions, we have no spent inputs and will return 0
  Future<Amount> _txSpentSum(int transactionId) async {
    final db = await _db;
    final res = await db.rawQuery('''
      SELECT COALESCE(SUM(o.amount_sat), 0) as total
      FROM tx_spent_outpoints s
      JOIN owned_outputs o ON s.outpoint_txid = o.txid AND s.outpoint_vout = o.vout
      WHERE s.transaction_id = ?
    ''', [transactionId]);

    final sum = res.first['total'] as int;

    return Amount(field0: BigInt.from(sum));
  }

  Future<Amount> _txOutputSum(int transactionId) async {
    final db = await _db;
    final res = await db.rawQuery('''
      SELECT COALESCE(SUM(amount_sat), 0) as total
      FROM tx_recipients
      WHERE transaction_id = ?
    ''', [transactionId]);

    return Amount(field0: BigInt.from(res.first['total'] as int));
  }

  Future<Amount> _txAssociatedOwnedOutputsSum(int transactionId) async {
    final db = await _db;
    final res = await db.rawQuery('''
      SELECT COALESCE(SUM(o.amount_sat), 0) as total
      FROM owned_outputs o
      JOIN transactions t ON o.txid = t.txid
      WHERE t.id = ?
    ''', [transactionId]);

    return Amount(field0: BigInt.from(res.first['total'] as int));
  }

  /// sum of all 'change' outputs, aka recipients that we detect as ourselves
  /// note: we also count outputs that we send to our receive address as 'change'!
  Future<Amount> _txChangeSum(
      int transactionId, String receiveCode, String changeCode) async {
    final db = await _db;
    final res = await db.rawQuery('''
      SELECT COALESCE(SUM(amount_sat), 0) as total
      FROM tx_recipients
      WHERE transaction_id = ?
      AND (payment_code = ? OR payment_code = ?)
    ''', [transactionId, receiveCode, changeCode]);

    final sum = res.first['total'] as int;

    return Amount(field0: BigInt.from(sum));
  }

  /// get the transaction fee, aka input_sum - output_sum
  Future<Amount> _txFee(int transactionId) async {
    final inputSum = await _txSpentSum(transactionId);

    final outputSum = await _txOutputSum(transactionId);

    // fee is inputs - outputs
    return inputSum - outputSum;
  }

  // returns all recipients for this transaction, with change outputs filtered out
  Future<List<Recipient>> _txRecipients(
      int transactionId, String receiveCode, String changeCode) async {
    final db = await _db;
    final res = await db.rawQuery('''
      SELECT *
      FROM tx_recipients
      WHERE transaction_id = ?
      AND payment_code != ?
      AND payment_code != ?
    ''', [transactionId, receiveCode, changeCode]);

    List<Recipient> result = List.empty(growable: true);

    for (final row in res) {
      result.add(Recipient(
          paymentCode: row['payment_code'] as String,
          amount: Amount(field0: BigInt.from(row['amount_sat'] as int))));
    }

    return result;
  }

  Future<List<OutPoint>> _txSpentOutpoints(int transactionId) async {
    final db = await _db;
    final res = await db.rawQuery('''
      SELECT *
      FROM tx_spent_outpoints
      WHERE transaction_id = ?
    ''', [transactionId]);

    List<OutPoint> result = List.empty(growable: true);

    for (final row in res) {
      result.add(OutPoint(
          txid: row['outpoint_txid'] as String,
          vout: row['outpoint_vout'] as int));
    }

    return result;
  }

  /// Get all transactions for UI display.
  Future<List<RecordedTransaction>> getAllTransactions(
      String receiveCode, String changeCode) async {
    final db = await _db;

    final transactions = await db.query('transactions',
        orderBy:
            'CASE WHEN confirmation_height IS NULL THEN 0 ELSE 1 END, confirmation_height DESC');

    final result = <RecordedTransaction>[];

    for (final row in transactions) {
      final transactionId = row['id'] as int;
      final txid = row['txid'] as String?;
      final confirmationHeight = row['confirmation_height'] as int?;
      final confirmationBlockhash = row['confirmation_blockhash'] as String?;
      final note = row['user_note'] as String?;
      final confirmationTimestamp = row['confirmation_timestamp'] as int?;

      final spentSum = await _txSpentSum(transactionId);

      if (spentSum == Amount.zero()) {
        // if spent sum is zero, we have not spent a single output during this transaction
        // in other words, this is an incoming transaction.
        // txid is always present for incoming transactions
        txid!;

        // for an incoming transaction we read all owned outputs that are created from this tx
        final receiveSum = await _txAssociatedOwnedOutputsSum(transactionId);

        result.add(RecordedTransactionIncoming(
          id: transactionId,
          note: note,
          confirmationTimestamp: confirmationTimestamp,
          txid: txid,
          amount: receiveSum,
          confirmationHeight: confirmationHeight,
          confirmationBlockhash: confirmationBlockhash,
        ));
      } else {
        // this is an outgoing transaction
        // there are 2 types of outgoing transactions: regular and 'unknown'

        final spentOutpoints = await _txSpentOutpoints(transactionId);

        // the 'change' of an outgoing transaction is all the recipients that have our receive or change payment code
        final changeSum =
            await _txChangeSum(transactionId, receiveCode, changeCode);

        final fee = await _txFee(transactionId);

        final recipients =
            await _txRecipients(transactionId, receiveCode, changeCode);

        if (txid != null) {
          result.add(RecordedTransactionOutgoing(
            id: transactionId,
            note: note,
            confirmationTimestamp: confirmationTimestamp,
            txid: txid,
            spentOutpoints: spentOutpoints,
            recipients: recipients,
            confirmationHeight: confirmationHeight,
            confirmationBlockhash: confirmationBlockhash,
            change: changeSum,
            fee: fee,
          ));
        } else {
          result.add(RecordedTransactionUnknownOutgoing(
            id: transactionId,
            note: note,
            confirmationTimestamp: confirmationTimestamp,
            amount: spentSum,
            confirmationHeight: confirmationHeight!,
            spentOutpoints: spentOutpoints,
          ));
        }
      }
    }

    return result;
  }

  /// Get sum of unconfirmed change from outgoing transactions.
  Future<Amount> getUnconfirmedChange(
      String receivePaymentCode, String changePaymentCode) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount_sat), 0) as total
      FROM tx_recipients r
      JOIN transactions t ON t.id = r.transaction_id
      WHERE t.confirmation_height IS NULL
      AND (r.payment_code = ? OR r.payment_code = ?)
    ''', [receivePaymentCode, changePaymentCode]);
    return Amount(field0: BigInt.from(result.first['total'] as int));
  }

  /// Add an incoming transaction.
  Future<void> addIncomingTransaction({
    required String txid,
    required int confirmationHeight,
    required String confirmationBlockhash,
  }) async {
    final db = await _db;
    await db.rawInsert('''
      INSERT INTO transactions (
        txid, confirmation_height, confirmation_blockhash
      ) VALUES (?, ?, ?) ON CONFLICT DO NOTHING
    ''', [txid, confirmationHeight, confirmationBlockhash]);
  }

  /// Add an outgoing transaction (when user sends).
  Future<void> addOutgoingTransaction({
    required List<OutPoint> spentOutpoints,
    required List<Recipient> recipients,
    String? txid,
    int? confirmationHeight,
    String? confirmationBlockhash,
  }) async {
    final db = await _db;

    await db.transaction((txn) async {
      final int transactionId = await txn.rawInsert('''
        INSERT INTO transactions (
          txid, confirmation_height, confirmation_blockhash
        ) VALUES (?, ?, ?)
      ''', [
        txid,
        confirmationHeight,
        confirmationBlockhash,
      ]);

      for (final outpoint in spentOutpoints) {
        await txn.rawInsert('''
          INSERT INTO tx_spent_outpoints (transaction_id, outpoint_txid, outpoint_vout)
          VALUES (?, ?, ?)
        ''', [transactionId, outpoint.txid, outpoint.vout]);
      }

      for (final recipient in recipients) {
        await txn.rawInsert('''
          INSERT INTO tx_recipients (transaction_id, payment_code, amount_sat)
          VALUES (?, ?, ?)
        ''', [transactionId, recipient.paymentCode, recipient.amount.toSat()]);
      }
    });
  }

  /// Confirm an outgoing transaction (during scan when we see it mined).
  Future<bool> confirmOutgoingTransaction({
    required String confirmedOutpointTxid,
    required int confirmedOutpointVout,
    required int confirmationHeight,
    required String confirmationBlockhash,
  }) async {
    final db = await _db;

    final result = await db.rawQuery('''
      SELECT t.id
      FROM transactions t
      JOIN tx_spent_outpoints s ON s.transaction_id = t.id
      WHERE s.outpoint_txid = ? 
        AND s.outpoint_vout = ?
      LIMIT 1
    ''', [confirmedOutpointTxid, confirmedOutpointVout]);

    if (result.isEmpty) {
      return false; // No matching outgoing transaction found
    }

    final transactionId = result.first['id'] as int;
    await db.rawUpdate('''
      UPDATE transactions
      SET confirmation_height = ?, confirmation_blockhash = ?
      WHERE id = ?
    ''', [confirmationHeight, confirmationBlockhash, transactionId]);

    Logger().i("Confirmed tx with id $transactionId");

    return true;
  }

  /// Get outpoints whose spending transaction has been broadcast but not yet confirmed.
  /// These must be included in the scan list so the scanner can detect when they are mined.
  Future<List<OutPoint>> getUnconfirmedSpentOutpoints() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT s.outpoint_txid, s.outpoint_vout
      FROM tx_spent_outpoints s
      JOIN transactions t ON t.id = s.transaction_id
      WHERE t.confirmation_height IS NULL AND t.confirmation_blockhash IS NULL
    ''');

    return rows
        .map((row) => OutPoint(
            txid: row['outpoint_txid'] as String,
            vout: row['outpoint_vout'] as int))
        .toList();
  }

  Future<void> saveConfirmationTimestamp(
      String txid, DateTime timestamp) async {
    final db = await _db;
    final timestampSeconds = timestamp.toSeconds();
    await db.rawUpdate(
      'UPDATE transactions SET confirmation_timestamp = ? WHERE txid = ?',
      [timestampSeconds, txid],
    );
  }

  /// Delete transactions above a certain blockheight (for resetToHeight).
  Future<void> deleteTransactionsAboveHeight(int height) async {
    final db = await _db;
    await db.delete('transactions',
        where: 'confirmation_height IS NULL OR confirmation_height > ?',
        whereArgs: [height]);
  }

  Future<void> saveNote(int transactionId, String note) async {
    final db = await _db;
    final updatedAt = DateTime.now().toSeconds();
    await db.rawUpdate(
      'UPDATE transactions SET user_note = ?, user_note_updated_at = ? WHERE id = ?',
      [note.isEmpty ? null : note, updatedAt, transactionId],
    );
  }
}

// ============================================
// LEGACY MIGRATION
// ============================================

/// Checks SharedPreferences for a legacy tx-history blob and, if found,
/// migrates it into SQLite and removes the old key.
///
/// LEGACY: TxHistory.decode() is only used here for migration.
/// Can be removed once no users remain on pre-SQLite versions.
Future<void> migrateTxHistoryFromSharedPreferences(String changeCode) async {
  final prefs = SharedPreferencesAsync();
  final encoded = await prefs.getString('txhistory');
  if (encoded == null) return;

  Logger().i("Migrating transaction history from SharedPreferences to SQLite");

  final history = LegacyTxHistoryStruct.decode(encodedHistory: encoded);
  final transactions = history.toApiTransactions();

  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    for (final tx in transactions) {
      await _insertTransaction(txn, tx, changeCode);
    }
  });

  Logger().i("Migrated ${transactions.length} transactions");
  await prefs.remove('txhistory');
}

Future<void> _insertTransaction(DatabaseExecutor executor,
    frb_legacy.RecordedTransaction tx, String changeCode) async {
  switch (tx) {
    case frb_legacy.RecordedTransaction_Incoming(:final field0):
      await executor.insert(
          'transactions',
          {
            'txid': field0.txid,
            'confirmation_height': field0.confirmationHeight,
            'confirmation_blockhash': field0.confirmationBlockhash,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      break;

    case frb_legacy.RecordedTransaction_Outgoing(:final field0):
      final txOutgoingId = await executor.insert(
          'transactions',
          {
            'txid': field0.txid,
            'confirmation_height': field0.confirmationHeight?.toInt(),
            'confirmation_blockhash': field0.confirmationBlockhash?.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      for (final outpoint in field0.spentOutpoints) {
        await executor.insert('tx_spent_outpoints', {
          'transaction_id': txOutgoingId,
          'outpoint_txid': outpoint.txid,
          'outpoint_vout': outpoint.vout,
        });
      }

      for (final recipient in field0.recipients) {
        await executor.insert('tx_recipients', {
          'transaction_id': txOutgoingId,
          'payment_code': recipient.paymentCode,
          'amount_sat': recipient.amount.toSat(),
        });
      }
      // in the legacy output format we used to store the change amount separately
      // to migrate, we need to add a new change output ourselves manually
      if (field0.change > Amount.zero()) {
        await executor.insert('tx_recipients', {
          'transaction_id': txOutgoingId,
          'payment_code': changeCode,
          'amount_sat': field0.change.toSat(),
        });
      }

      break;

    case frb_legacy.RecordedTransaction_UnknownOutgoing(:final field0):
      final txOutgoingId = await executor.insert('transactions', {
        'txid': null,
        'confirmation_height': field0.confirmationHeight,
        'confirmation_blockhash': field0.confirmationBlockhash,
      });

      for (final outpoint in field0.spentOutpoints) {
        await executor.insert('tx_spent_outpoints', {
          'transaction_id': txOutgoingId,
          'outpoint_txid': outpoint.txid,
          'outpoint_vout': outpoint.vout,
        });
      }
      break;
  }
}
