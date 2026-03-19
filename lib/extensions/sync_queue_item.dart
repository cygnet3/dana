import 'package:danawallet/generated/rust/api/structs/sync_queue_item.dart';

extension SyncQueueItemExtension on SyncQueueItem {
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'start': start,
      'end': end,
    };
  }

  static SyncQueueItem fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'],
      start: map['start'],
      end: map['end'],
    );
  }
}
