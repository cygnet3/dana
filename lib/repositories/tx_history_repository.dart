import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/generated/rust/api/legacy/history.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/outpoint.dart';
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
    await db.delete('tx_outgoing');
    await db.delete('tx_recipients');
    await db.delete('tx_spent_outpoints');
    await db.delete('tx_incoming');
  }

  /// Get all transactions for UI display.
  Future<List<RecordedTransaction>> getAllTransactions() async {
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

    final result = <RecordedTransaction>[];

    // Process incoming transactions
    for (final row in incomingRows) {
      final txid = row['txid'] as String;

      result.add(RecordedTransaction.incoming(
        RecordedTransactionIncoming(
          txid: txid,
          amount:
              ApiAmount(field0: BigInt.from(row['amount_received_sat'] as int)),
          confirmationHeight: row['confirmation_height'] as int?,
          confirmationBlockhash: row['confirmation_blockhash'] as String?,
        ),
      ));
    }

    // Process outgoing transactions
    for (final row in outgoingRows) {
      final txOutgoingId = row['id'] as int;
      final txid = row['txid'] as String?;
      final amountSpentSat = row['amount_spent_sat'] as int;

      // Fetch spent outpoints
      final spentRows = await db.rawQuery('''
        SELECT outpoint_txid, outpoint_vout
        FROM tx_spent_outpoints
        WHERE tx_outgoing_id = ?
      ''', [txOutgoingId]);
      final spentOutpoints = spentRows
          .map((r) => OutPoint(
              txid: r['outpoint_txid'] as String,
              vout: r['outpoint_vout'] as int))
          .toList();

      // Fetch recipients (empty for unknown-outgoing)
      final recipientRows = await db.rawQuery('''
        SELECT payment_code, amount_sat
        FROM tx_recipients
        WHERE tx_outgoing_id = ?
      ''', [txOutgoingId]);
      final recipients = recipientRows
          .map((r) => ApiRecipient(
                paymentCode: r['payment_code'] as String,
                amount: ApiAmount(field0: BigInt.from(r['amount_sat'] as int)),
              ))
          .toList();

      if (txid == null) {
        result.add(RecordedTransaction.unknownOutgoing(
          RecordedTransactionUnknownOutgoing(
            amount: ApiAmount(field0: BigInt.from(amountSpentSat)),
            confirmationHeight: row['confirmation_height'] as int,
            confirmationBlockhash: row['confirmation_blockhash'] as String?,
            spentOutpoints: spentOutpoints,
          ),
        ));
      } else {
        result.add(RecordedTransaction.outgoing(
          RecordedTransactionOutgoing(
            txid: txid,
            spentOutpoints: spentOutpoints,
            recipients: recipients,
            confirmationHeight: row['confirmation_height'] as int?,
            confirmationBlockhash: row['confirmation_blockhash'] as String?,
            change:
                ApiAmount(field0: BigInt.from(row['change_sat'] as int? ?? 0)),
            fee: ApiAmount(field0: BigInt.from(row['fee_sat'] as int? ?? 0)),
          ),
        ));
      }
    }

    // Sort by confirmation height (most recent first)
    result.sort((a, b) {
      int getConfirmationHeight(RecordedTransaction tx) {
        return switch (tx) {
          RecordedTransaction_Incoming(:final field0) =>
            field0.confirmationHeight ?? 9999999999,
          RecordedTransaction_Outgoing(:final field0) =>
            field0.confirmationHeight ?? 9999999999,
          RecordedTransaction_UnknownOutgoing(:final field0) =>
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
    required List<OutPoint> spentOutpoints,
    required List<ApiRecipient> recipients,
    String? txid,
    int? changeSat,
    int? feeSat,
    int? amountSpentSat,
  }) async {
    final db = await _db;

    await db.transaction((txn) async {
      final totalRecipientsAmount = recipients.fold<int>(
        0,
        (sum, r) => sum + r.amount.field0.toInt(),
      );
      final resolvedAmountSpentSat = amountSpentSat ??
          (totalRecipientsAmount + (feeSat ?? 0) + (changeSat ?? 0));

      final int txOutgoingId = await txn.rawInsert('''
        INSERT OR REPLACE INTO tx_outgoing (
          txid, amount_spent_sat, confirmation_height, confirmation_blockhash, change_sat, fee_sat
        ) VALUES (?, ?, ?, ?, ?, ?)
      ''', [
        txid,
        resolvedAmountSpentSat,
        null,
        null,
        changeSat,
        feeSat,
      ]);

      for (final outpoint in spentOutpoints) {
        await txn.rawInsert('''
          INSERT INTO tx_spent_outpoints (tx_outgoing_id, outpoint_txid, outpoint_vout)
          VALUES (?, ?, ?)
        ''', [txOutgoingId, outpoint.txid, outpoint.vout]);
      }

      for (final recipient in recipients) {
        await txn.rawInsert('''
          INSERT INTO tx_recipients (tx_outgoing_id, payment_code, amount_sat)
          VALUES (?, ?, ?)
        ''', [txOutgoingId, recipient.paymentCode, recipient.amount.toSat()]);
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
      SELECT h.id
      FROM tx_outgoing h
      JOIN tx_spent_outpoints s ON s.tx_outgoing_id = h.id
      WHERE s.outpoint_txid = ? 
        AND s.outpoint_vout = ?
      LIMIT 1
    ''', [spentOutpointTxid, spentOutpointVout]);

    if (result.isEmpty) {
      return false; // No matching outgoing transaction found
    }

    final txOutgoingId = result.first['id'] as int;
    await db.rawUpdate('''
      UPDATE tx_outgoing
      SET confirmation_height = ?, confirmation_blockhash = ?
      WHERE id = ?
    ''', [confirmationHeight, confirmationBlockhash, txOutgoingId]);

    return true;
  }

  /// Get outpoints whose spending transaction has been broadcast but not yet confirmed.
  /// These must be included in the scan list so the scanner can detect when they are mined.
  Future<List<OutPoint>> getUnconfirmedSpentOutpoints() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT s.outpoint_txid, s.outpoint_vout
      FROM tx_spent_outpoints s
      JOIN tx_outgoing o ON o.id = s.tx_outgoing_id
      WHERE o.confirmation_height IS NULL AND o.confirmation_blockhash IS NULL
    ''');

    return rows
        .map((row) => OutPoint(
            txid: row['outpoint_txid'] as String,
            vout: row['outpoint_vout'] as int))
        .toList();
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

  final history = LegacyTxHistoryStruct.decode(encodedHistory: encoded);
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
    DatabaseExecutor executor, RecordedTransaction tx) async {
  switch (tx) {
    case RecordedTransaction_Incoming(:final field0):
      await executor.insert('tx_incoming', {
        'txid': field0.txid,
        'amount_received_sat': field0.amount.field0.toInt(),
        'confirmation_height': field0.confirmationHeight,
        'confirmation_blockhash': field0.confirmationBlockhash,
      });
      break;

    case RecordedTransaction_Outgoing(:final field0):
      final totalAmount = field0.recipients
          .fold<int>(0, (sum, r) => sum + r.amount.field0.toInt());

      final txOutgoingId = await executor.insert('tx_outgoing', {
        'txid': field0.txid,
        'amount_spent_sat': totalAmount + field0.fee.field0.toInt(),
        'confirmation_height': field0.confirmationHeight?.toInt(),
        'confirmation_blockhash': field0.confirmationBlockhash?.toString(),
        'change_sat': field0.change.field0.toInt(),
        'fee_sat': field0.fee.field0.toInt(),
      });

      for (final outpoint in field0.spentOutpoints) {
        await executor.insert('tx_spent_outpoints', {
          'tx_outgoing_id': txOutgoingId,
          'outpoint_txid': outpoint.txid,
          'outpoint_vout': outpoint.vout,
        });
      }

      for (final recipient in field0.recipients) {
        await executor.insert('tx_recipients', {
          'tx_outgoing_id': txOutgoingId,
          'payment_code': recipient.paymentCode,
          'amount_sat': recipient.amount.toSat(),
        });
      }
      break;

    case RecordedTransaction_UnknownOutgoing(:final field0):
      final txOutgoingId = await executor.insert('tx_outgoing', {
        'txid': null,
        'amount_spent_sat': field0.amount.toSat(),
        'confirmation_height': field0.confirmationHeight,
        'confirmation_blockhash': field0.confirmationBlockhash,
        'change_sat': null,
        'fee_sat': null,
      });

      for (final outpoint in field0.spentOutpoints) {
        await executor.insert('tx_spent_outpoints', {
          'tx_outgoing_id': txOutgoingId,
          'outpoint_txid': outpoint.txid,
          'outpoint_vout': outpoint.vout,
        });
      }
      break;
  }
}
