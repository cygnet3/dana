import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/generated/rust/api/history.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/generated/rust/api/structs/recorded_transaction.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class TxHistoryRepository {
  // private constructor
  TxHistoryRepository._();

  // singleton
  static final instance = TxHistoryRepository._();

  Future<Database> get _db async => await DatabaseHelper.instance.database;

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
        ''', [txid, recipient.address, recipient.amount.toSat()]);
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

// ============================================
// LEGACY MIGRATION
// ============================================

/// Checks SharedPreferences for a legacy tx-history blob and, if found,
/// migrates it into SQLite and removes the old key.
///
/// LEGACY: TxHistory.decode() is only used here for migration.
/// Can be removed once no users remain on pre-SQLite versions.
Future<void> migrateTxHistoryFromSharedPreferences() async {
  final prefs = SharedPreferencesAsync();
  final encoded = await prefs.getString('txhistory');
  if (encoded == null) return;

  Logger().i("Migrating transaction history from SharedPreferences to SQLite");

  final history = TxHistory.decode(encodedHistory: encoded);
  final transactions = history.toApiTransactions();

  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    for (final tx in transactions) {
      await _insertTransaction(txn, tx);
    }
  });

  Logger().i("Migrated ${transactions.length} transactions");
  await prefs.remove('txhistory');
}

Future<void> _insertTransaction(
    DatabaseExecutor executor, ApiRecordedTransaction tx) async {
  switch (tx) {
    case ApiRecordedTransaction_Incoming(:final field0):
      await executor.insert('tx_incoming', {
        'txid': field0.txid,
        'amount_received_sat': field0.amount.field0.toInt(),
        'confirmation_height': field0.confirmationHeight,
        'confirmation_blockhash': field0.confirmationBlockhash,
      });
      break;

    case ApiRecordedTransaction_Outgoing(:final field0):
      final totalAmount = field0.recipients
          .fold<int>(0, (sum, r) => sum + r.amount.field0.toInt());

      await executor.insert('tx_outgoing', {
        'txid': field0.txid,
        'amount_spent_sat': totalAmount + field0.fee.field0.toInt(),
        'confirmation_height': field0.confirmationHeight?.toInt(),
        'confirmation_blockhash': field0.confirmationBlockhash?.toString(),
        'change_sat': field0.change.field0.toInt(),
        'fee_sat': field0.fee.field0.toInt(),
      });

      for (final outpoint in field0.spentOutpoints) {
        final (outTxid, outVout) = _parseOutpoint(outpoint);
        await executor.insert('tx_spent_outpoints', {
          'txid': field0.txid,
          'outpoint_txid': outTxid,
          'outpoint_vout': outVout,
        });
      }

      for (final recipient in field0.recipients) {
        await executor.insert('tx_recipients', {
          'txid': field0.txid,
          'address': recipient.address,
          'amount_sat': recipient.amount.toSat(),
        });
      }
      break;

    case ApiRecordedTransaction_UnknownOutgoing(:final field0):
      // Don't create a history entry for unknown outgoing transactions.
      // Just mark the outputs as spent with unknown txid.
      for (final outpoint in field0.spentOutpoints) {
        final (outTxid, outVout) = _parseOutpoint(outpoint);
        await executor.update(
          'owned_outputs',
          {
            'spending_txid': null,
            'mined_in_block': field0.confirmationBlockhash,
          },
          where: 'txid = ? AND vout = ?',
          whereArgs: [outTxid, outVout],
        );
      }
      break;
  }
}

(String, int) _parseOutpoint(String outpoint) {
  final parts = outpoint.split(':');
  return (parts[0], int.parse(parts[1]));
}
