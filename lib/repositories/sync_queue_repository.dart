import 'package:danawallet/extensions/sync_queue_item.dart';
import 'package:danawallet/generated/rust/api/structs/sync_queue_item.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class SyncQueueRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insertNewSyncQueueItem(int start, int end) async {
    final db = await _dbHelper.database;
    return await db.insert(
      'sync_queue',
      {"start": start, "end": end},
      conflictAlgorithm: ConflictAlgorithm.fail,
    );
  }

  Future<int> processUpdate(int id, int height) async {
    final items = await getQueueItems();
    final item = items.firstWhere((item) => item.id == id);

    if (height <= item.start) {
      return await deleteSyncQueueItem(item.id);
    } else {
      final db = await _dbHelper.database;
      return await db.update(
        'sync_queue',
        {"end": height - 1},
        where: 'id = ?',
        whereArgs: [item.id],
      );
    }
  }

  Future<int> deleteSyncQueueItem(int id) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<SyncQueueItem>> getQueueItems() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'sync_queue',
    );

    if (maps.isEmpty) return List.empty();

    return maps.map((map) => SyncQueueItemExtension.fromMap(map)).toList();
  }

  Future<int> getBlockCountToSync() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
        "SELECT COALESCE(SUM(end - start), 0) AS total FROM sync_queue");

    return result[0]['total'] as int;
  }
}
