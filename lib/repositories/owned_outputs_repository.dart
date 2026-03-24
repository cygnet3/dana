import 'dart:convert';
import 'dart:typed_data';

import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/outpoint.dart';
import 'package:danawallet/generated/rust/lib.dart';
import 'package:danawallet/generated/rust/stream.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class OwnedOutputsRepository {
  // private constructor
  OwnedOutputsRepository._();

  // singleton
  static final instance = OwnedOutputsRepository._();

  Future<Database> get _db async => await DatabaseHelper.instance.database;

  Future<void> reset() async {
    final db = await _db;
    await db.rawDelete('DELETE FROM owned_outputs');
  }

  /// Get total balance of unspent outputs in satoshis.
  Future<ApiAmount> getUnspentBalance() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount_sat), 0) as total 
      FROM owned_outputs 
      WHERE spending_txid IS NULL AND mined_in_block IS NULL
    ''');
    return ApiAmount(field0: BigInt.from(result.first['total'] as int));
  }

  /// Get all unspent outputs for spending.
  Future<List<OwnedOutput>> getUnspentOutputs() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT *
      FROM owned_outputs
      WHERE spending_txid IS NULL AND mined_in_block IS NULL
    ''');

    final result = <OwnedOutput>[];
    for (final row in rows) {
      result.add(OwnedOutput(
        txid: row['txid'] as String,
        vout: row['vout'] as int,
        blockheight: row['blockheight'] as int,
        tweak: U8Array32(row['tweak'] as Uint8List),
        amount: ApiAmountExtension.fromDbValue(row['amount']),
        script: row['script'] as String,
        label: row['label'] as String?,
        spendingTxid: row['spending_txid'] as String?,
        minedInBlock: row['mined_in_block'] as String?,
      ));
    }
    return result;
  }

  /// Get outpoints that are not yet mined (for scanning).
  Future<List<String>> getNotMinedOutpoints() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT txid, vout
      FROM owned_outputs
      WHERE mined_in_block IS NULL
    ''');

    return rows.map((row) => '${row['txid']}:${row['vout']}').toList();
  }

  /// Get amount for a specific outpoint.
  Future<int?> getOutputAmount(String txid, int vout) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT amount_sat FROM owned_outputs 
      WHERE txid = ? AND vout = ?
    ''', [txid, vout]);

    if (rows.isEmpty) return null;
    return rows.first['amount_sat'] as int;
  }

  /// Insert a new output (during scanning).
  Future<void> insertOutput({
    required OwnedOutput output,
  }) async {
    final db = await _db;
    try {
      await db.rawInsert('''
        INSERT OR FAIL INTO owned_outputs (
          txid, vout, blockheight, tweak, amount_sat, script, label, spending_txid, mined_in_block
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        output.txid,
        output.vout,
        output.blockheight,
        Uint8List.fromList(output.tweak),
        output.amount.toSat(),
        output.script,
        output.label,
        output.spendingTxid,
        output.minedInBlock,
      ]);
    } catch (e) {
      Logger().e("Failed to insert output: $e");
      Logger().e("Output: ${output.toString()}");
    }
  }

  /// Mark an output as spent (when user broadcasts a transaction).
  Future<void> markOutputSpent(
      OutPoint outpoint, String spendingTxid) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE owned_outputs
      SET spending_txid = ?
      WHERE txid = ? AND vout = ?
    ''', [spendingTxid, outpoint.txid, outpoint.vout]);
  }

  /// Mark an output as mined (during scanning).
  Future<void> markOutputMined(String txid, int vout, String minedInBlock) async {
    final db = await _db;
    await db.update(
      'owned_outputs',
      {'mined_in_block': minedInBlock},
      where: 'txid = ? AND vout = ?',
      whereArgs: [txid, vout],
    );
  }

  /// Delete outputs above a certain blockheight (for resetToHeight).
  Future<void> deleteOutputsAboveHeight(int height) async {
    final db = await _db;
    await db.rawDelete('''
      DELETE FROM owned_outputs
      WHERE blockheight > ?
    ''', [height]);
  }
}

// ============================================
// LEGACY MIGRATION
// ============================================

/// Checks SharedPreferences for a legacy owned-outputs blob and, if found,
/// migrates it into SQLite and removes the old key.
///
/// LEGACY: can be removed once no users remain on pre-SQLite versions.
///
/// The old spend_status was a serde enum:
///   "Unspent"              → spending_txid: null, mined_in_block: null
///   {"Spent": "txid"}      → spending_txid: txid, mined_in_block: null
///   {"Mined": "blockhash"} → spending_txid: null, mined_in_block: blockhash
Future<void> migrateOutputsFromSharedPreferences() async {
  final prefs = SharedPreferencesAsync();
  final json = await prefs.getString('ownedoutputs');
  if (json == null) return;

  Logger().i("Migrating owned outputs from SharedPreferences to SQLite");

  final Map<String, dynamic> decoded = jsonDecode(json);
  int migrated = 0;

  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    for (final entry in decoded.entries) {
      final Map<String, dynamic> output = entry.value;
      final spendStatus = output['spend_status'];

      String? spendingTxid;
      String? minedInBlock;

      if (spendStatus is Map<String, dynamic>) {
        if (spendStatus.containsKey('Spent')) {
          spendingTxid = spendStatus['Spent'] as String?;
        } else if (spendStatus.containsKey('Mined')) {
          minedInBlock = spendStatus['Mined'] as String?;
        }
      }
      // else: "Unspent" string — both remain null

      final outpoint = _parseOutpoint(entry.key);
      final List<dynamic> tweakList = output['tweak'];

      await txn.insert('owned_outputs', {
        'txid': outpoint.$1,
        'vout': outpoint.$2,
        'blockheight': output['blockheight'] as int,
        'tweak': Uint8List.fromList(tweakList.cast<int>()),
        'amount_sat': output['amount'] as int,
        'script': output['script'] as String,
        'label': output['label'] as String?,
        'spending_txid': spendingTxid,
        'mined_in_block': minedInBlock,
      });
      migrated++;
    }
  });

  Logger().i("Migrated $migrated outputs (of ${decoded.length} total)");
  await prefs.remove('ownedoutputs');
}

(String, int) _parseOutpoint(String outpoint) {
  final parts = outpoint.split(':');
  return (parts[0], int.parse(parts[1]));
}
