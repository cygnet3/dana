import 'dart:typed_data';

import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/generated/rust/api/legacy/owned_outputs.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/outpoint.dart';
import 'package:danawallet/generated/rust/api/structs/owned_output.dart';
import 'package:danawallet/generated/rust/lib.dart';
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
      SELECT COALESCE(SUM(o.amount_sat), 0) as total
      FROM owned_outputs o
      LEFT JOIN tx_spent_outpoints s ON s.outpoint_txid = o.txid AND s.outpoint_vout = o.vout
      WHERE s.transaction_id IS NULL
    ''');
    return ApiAmount(field0: BigInt.from(result.first['total'] as int));
  }

  /// Get all unspent outputs for spending.
  Future<List<OwnedOutput>> getUnspentOutputs() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT o.*
      FROM owned_outputs o
      LEFT JOIN tx_spent_outpoints s ON s.outpoint_txid = o.txid AND s.outpoint_vout = o.vout
      WHERE s.transaction_id IS NULL
    ''');

    final result = <OwnedOutput>[];
    for (final row in rows) {
      final labelbytes = row['label'] as Uint8List?;
      U8Array32? label;
      if (labelbytes != null) {
        label = U8Array32(labelbytes);
      }

      result.add(OwnedOutput(
        outpoint:
            OutPoint(txid: row['txid'] as String, vout: row['vout'] as int),
        tweak: U8Array32(row['tweak'] as Uint8List),
        amount: ApiAmountExtension.fromDbValue(row['amount_sat']),
        script: row['script'] as Uint8List,
        label: label,
      ));
    }
    return result;
  }

  /// Get all unspent outpoints to pass to the scanner (so it can detect spends).
  Future<List<OutPoint>> getUnspentOutpoints() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT o.txid, o.vout
      FROM owned_outputs o
      LEFT JOIN tx_spent_outpoints s ON s.outpoint_txid = o.txid AND s.outpoint_vout = o.vout
      WHERE s.transaction_id IS NULL
    ''');

    return rows
        .map((row) =>
            OutPoint(txid: row['txid'] as String, vout: row['vout'] as int))
        .toList();
  }

  /// Get amount for a specific outpoint.
  Future<int?> getOutputAmount(OutPoint outpoint) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT amount_sat FROM owned_outputs 
      WHERE txid = ? AND vout = ?
    ''', [outpoint.txid, outpoint.vout]);

    if (rows.isEmpty) return null;
    return rows.first['amount_sat'] as int;
  }

  /// Insert a new output (during scanning).
  Future<void> insertOutput({
    required OwnedOutput output,
  }) async {
    final db = await _db;
    try {
      Uint8List? label;
      if (output.label != null) {
        label = Uint8List.fromList(output.label!);
      }

      await db.rawInsert('''
        INSERT OR FAIL INTO owned_outputs (
          txid, vout, tweak, amount_sat, script, label
        ) VALUES (?, ?, ?, ?, ?, ?)
      ''', [
        output.outpoint.txid,
        output.outpoint.vout,
        Uint8List.fromList(output.tweak),
        output.amount.toSat(),
        output.script,
        label,
      ]);
    } catch (e) {
      Logger().e("Failed to insert output: $e");
      Logger().e("Output: ${output.toString()}");
    }
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
Future<void> migrateOutputsFromSharedPreferences() async {
  final prefs = SharedPreferencesAsync();
  final encoded = await prefs.getString('ownedoutputs');
  if (encoded == null) return;

  Logger().i("Migrating owned outputs from SharedPreferences to SQLite");

  final decoded = LegacyOwnedOutputsStruct.decode(encodedOutputs: encoded);
  final outputs = decoded.toApiOwnedOutputs();

  int migrated = 0;

  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    for (final output in outputs) {
      Uint8List? label;
      if (output.label != null) {
        label = Uint8List.fromList(output.label!);
      }
      await txn.insert('owned_outputs', {
        'txid': output.outpoint.txid,
        'vout': output.outpoint.vout,
        'tweak': Uint8List.fromList(output.tweak.toList()),
        'amount_sat': output.amount.toSat(),
        'script': output.script,
        'label': label,
      });
      migrated++;
    }
  });

  Logger().i("Migrated $migrated outputs (of ${outputs.length} total)");
  await prefs.remove('ownedoutputs');
}
