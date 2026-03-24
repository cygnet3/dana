import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/generated/rust/api/structs/recorded_transaction.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class TxHistoryRepository {
  // private constructor
  TxHistoryRepository._();

  // singleton
  static final instance = TxHistoryRepository._();

  Future<Database> get _db async => await DatabaseHelper.instance.database;

  /// Converts a [BigInt] satoshi amount to [int] for SQLite storage.
  /// Throws a [StateError] if the value exceeds the safe integer range,
  /// preventing silent data corruption on overflow.
  static int _bigIntToSat(BigInt value) {
    if (!value.isValidInt) {
      throw StateError('Amount overflows int: $value');
    }
    return value.toInt();
  }

  Future<void> reset() async {
    final db = await _db;
    await db.rawDelete('DELETE FROM tx_incoming');
    await db.rawDelete('DELETE FROM tx_outgoing');
  }

  /// Get all transactions for UI display.
  Future<List<ApiRecordedTransaction>> getAllTransactions() async {
    final db = await _db;

    // Get all incoming transactions
    final incomingRows = await db.rawQuery('''
      SELECT *
      FROM tx_incoming
      ORDER BY created_at DESC
    ''');

    // Get all outgoing transactions
    final outgoingRows = await db.rawQuery('''
      SELECT *
      FROM tx_outgoing
      ORDER BY created_at DESC
    ''');

    final result = <ApiRecordedTransaction>[];

    // Process incoming transactions
    for (final row in incomingRows) {
      final txid = row['txid'] as String;

      result.add(ApiRecordedTransaction.incoming(
        ApiRecordedTransactionIncoming(
          txid: txid,
          amount: ApiAmount(
              field0: BigInt.from(row['amount_received_sat'] as int)),
          confirmationHeight: row['confirmation_height'] as int?,
          confirmationBlockhash: row['confirmation_blockhash'] as String?,
        ),
      ));
    }

    // Process outgoing transactions
    for (final row in outgoingRows) {
      final txid = row['txid'] as String;

      // Fetch spent outpoints
      final spentRows = await db.rawQuery('''
        SELECT outpoint_txid, outpoint_vout
        FROM tx_spent_outpoints
        WHERE txid = ?
      ''', [txid]);
      final spentOutpoints = spentRows
          .map((r) => '${r['outpoint_txid']}:${r['outpoint_vout']}')
          .toList();

      // Fetch recipients
      final recipientRows = await db.rawQuery('''
        SELECT address, amount_sat
        FROM tx_recipients
        WHERE txid = ?
      ''', [txid]);
      final recipients = recipientRows
          .map((r) => ApiRecipient(
                address: r['address'] as String,
                amount: ApiAmount(field0: BigInt.from(r['amount_sat'] as int)),
              ))
          .toList();

      result.add(ApiRecordedTransaction.outgoing(
        ApiRecordedTransactionOutgoing(
          txid: txid,
          spentOutpoints: spentOutpoints,
          recipients: recipients,
          confirmationHeight: row['confirmation_height'] as int?,
          confirmationBlockhash: row['confirmation_blockhash'] as String?,
          change: ApiAmount(field0: BigInt.from(row['change_sat'] as int? ?? 0)),
          fee: ApiAmount(field0: BigInt.from(row['fee_sat'] as int? ?? 0)),
        ),
      ));
    }

    // Sort by confirmation height (most recent first)
    result.sort((a, b) {
      int getConfirmationHeight(ApiRecordedTransaction tx) {
        return switch (tx) {
          ApiRecordedTransaction_Incoming(:final field0) =>
            field0.confirmationHeight ?? 9999999999,
          ApiRecordedTransaction_Outgoing(:final field0) =>
            field0.confirmationHeight ?? 9999999999,
          ApiRecordedTransaction_UnknownOutgoing(:final field0) =>
            field0.confirmationHeight,
        };
      }

      final aHeight = getConfirmationHeight(a);
      final bHeight = getConfirmationHeight(b);
      return bHeight.compareTo(aHeight);
    });

    return result;
  }

  /// Get sum of unconfirmed change from outgoing transactions.
  Future<ApiAmount> getUnconfirmedChange() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(change_sat), 0) as total 
      FROM tx_outgoing 
      WHERE confirmation_height IS NULL
    ''');
    return ApiAmount(field0: BigInt.from(result.first['total'] as int));
  }

  /// Check if a txid is from an outgoing transaction we sent (self-send check).
  Future<bool> isOwnOutgoingTx(String txid) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT 1 FROM tx_outgoing 
      WHERE txid = ?
      LIMIT 1
    ''', [txid]);
    return result.isNotEmpty;
  }

  /// Add an incoming transaction.
  Future<void> addIncomingTransaction({
    required String txid,
    required ApiAmount amountSat,
    required int confirmationHeight,
    required String confirmationBlockhash,
  }) async {
    final db = await _db;
    await db.rawInsert('''
      INSERT OR REPLACE INTO tx_incoming (
        txid, amount_received_sat, confirmation_height, confirmation_blockhash
      ) VALUES (?, ?, ?, ?)
    ''', [txid, amountSat.toSat(), confirmationHeight, confirmationBlockhash]);
  }

  /// Add an outgoing transaction (when user sends).
  Future<void> addOutgoingTransaction({
    required String txid,
    required List<(String, int, int)> spentOutpoints, // (txid, vout, amount)
    required List<ApiRecipient> recipients,
    int? changeSat,
    int? feeSat,
  }) async {
    final db = await _db;

    await db.transaction((txn) async {
      final totalAmount =
          recipients.fold<int>(0, (sum, r) => sum + r.amount.field0.toInt());

      await txn.rawInsert('''
        INSERT OR REPLACE INTO tx_outgoing (
          txid, amount_spent_sat, confirmation_height, confirmation_blockhash, change_sat, fee_sat
        ) VALUES (?, ?, ?, ?, ?, ?)
      ''', [
        txid,
        totalAmount + (feeSat ?? 0) + (changeSat ?? 0),
        null,
        null,
        changeSat,
        feeSat,
      ]);

      for (final (outTxid, outVout, _) in spentOutpoints) {
        await txn.rawInsert('''
          INSERT INTO tx_spent_outpoints (txid, outpoint_txid, outpoint_vout)
          VALUES (?, ?, ?)
        ''', [txid, outTxid, outVout]);
      }

      for (final recipient in recipients) {
        await txn.rawInsert('''
          INSERT INTO tx_recipients (txid, address, amount_sat)
          VALUES (?, ?, ?)
        ''', [txid, recipient.address, _bigIntToSat(recipient.amount.field0)]);
      }
    });
  }

  /// Confirm an outgoing transaction (during scan when we see it mined).
  Future<bool> confirmOutgoingTransaction({
    required String spentOutpointTxid,
    required int spentOutpointVout,
    required int confirmationHeight,
    required String confirmationBlockhash,
  }) async {
    final db = await _db;

    final result = await db.rawQuery('''
      SELECT h.txid 
      FROM tx_outgoing h
      JOIN tx_spent_outpoints s ON s.txid = h.txid
      WHERE s.outpoint_txid = ? 
        AND s.outpoint_vout = ?
      LIMIT 1
    ''', [spentOutpointTxid, spentOutpointVout]);

    if (result.isEmpty) {
      return false; // No matching outgoing transaction found
    }

    final txid = result.first['txid'] as String;
    await db.rawUpdate('''
      UPDATE tx_outgoing
      SET confirmation_height = ?, confirmation_blockhash = ?
      WHERE txid = ?
    ''', [confirmationHeight, confirmationBlockhash, txid]);

    return true;
  }

  /// Delete transactions above a certain blockheight (for resetToHeight).
  Future<void> deleteTransactionsAboveHeight(int height) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.rawDelete('''
        DELETE FROM tx_incoming
        WHERE confirmation_height IS NOT NULL AND confirmation_height > ?
      ''', [height]);
      await txn.rawDelete('''
        DELETE FROM tx_outgoing
        WHERE confirmation_height IS NOT NULL AND confirmation_height > ?
      ''', [height]);
    });
  }
}
