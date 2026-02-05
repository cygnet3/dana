import 'package:danawallet/repositories/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class TransactionNotesRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // private constructor
  TransactionNotesRepository._();

  // singleton instance
  static final instance = TransactionNotesRepository._();

  Future<void> saveNote(String txid, String note) async {
    final db = await _dbHelper.database;
    final storedNote = note.isEmpty ? null : note;
    final updatedAt =
        storedNote == null ? null : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await db.transaction((txn) async {
      final incomingUpdated = await _updateNote(
        txn,
        table: 'tx_incoming',
        txid: txid,
        note: storedNote,
        updatedAt: updatedAt,
      );
      if (incomingUpdated == 0) {
        await _updateNote(
          txn,
          table: 'tx_outgoing',
          txid: txid,
          note: storedNote,
          updatedAt: updatedAt,
        );
      }
    });
  }

  Future<String?> getNote(String txid) async {
    final db = await _dbHelper.database;
    final incoming = await _loadNote(db, table: 'tx_incoming', txid: txid);
    if (incoming != null) return incoming;
    return await _loadNote(db, table: 'tx_outgoing', txid: txid);
  }

  Future<void> deleteNote(String txid) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final incomingUpdated = await _updateNote(
        txn,
        table: 'tx_incoming',
        txid: txid,
        note: null,
        updatedAt: null,
      );
      if (incomingUpdated == 0) {
        await _updateNote(
          txn,
          table: 'tx_outgoing',
          txid: txid,
          note: null,
          updatedAt: null,
        );
      }
    });
  }

  Future<int> _updateNote(
    DatabaseExecutor db, {
    required String table,
    required String txid,
    required String? note,
    required int? updatedAt,
  }) async {
    return await db.update(
      table,
      {
        'user_note': note,
        'user_note_updated_at': updatedAt,
      },
      where: 'txid = ?',
      whereArgs: [txid],
    );
  }

  Future<String?> _loadNote(
    DatabaseExecutor db, {
    required String table,
    required String txid,
  }) async {
    final rows = await db.query(
      table,
      columns: ['user_note'],
      where: 'txid = ?',
      whereArgs: [txid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['user_note'] as String?;
  }
}
