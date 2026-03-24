import 'dart:typed_data';

import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/lib.dart';
import 'package:danawallet/generated/rust/stream.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:logger/logger.dart';
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
      String txid, int vout, String spendingTxid) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE owned_outputs
      SET spending_txid = ?
      WHERE txid = ? AND vout = ?
    ''', [spendingTxid, txid, vout]);
  }

  /// Mark an output as mined (during scanning).
  Future<void> markOutputMined(String txid, int vout, String minedInBlock,
      {String? spendingTxid}) async {
    final db = await _db;
    final updates = <String, Object?>{'mined_in_block': minedInBlock};
    if (spendingTxid != null) {
      updates['spending_txid'] = spendingTxid;
    }
    await db.update(
      'owned_outputs',
      updates,
      where: 'txid = ? AND vout = ?',
      whereArgs: [txid, vout],
    );
  }

  /// Mark outputs as spent without creating a history entry (unknown spend case).
  /// Used when outputs are spent from another device/wallet.
  Future<void> markOutputsSpentUnknown({
    required List<(String, int, int)> spentOutpoints, // (txid, vout, amount)
    required String minedInBlock,
  }) async {
    final db = await _db;

    await db.transaction((txn) async {
      for (final (outTxid, outVout, _) in spentOutpoints) {
        await txn.update(
          'owned_outputs',
          {
            'spending_txid': null, // Unknown txid
            'mined_in_block': minedInBlock,
          },
          where: 'txid = ? AND vout = ?',
          whereArgs: [outTxid, outVout],
        );
      }
    });
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
