import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// D7/D10 acceptance: frigate disclosure records are append-only within a
/// wallet lifetime and carry url + visibility + date; the one-time public
/// warning flag (D6) is per-wallet and one-way. Runs against the real
/// [WalletRepository] over an in-memory SharedPreferencesAsync platform.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // WalletRepository.instance captures the platform at first construction
  // (SharedPreferencesAsync caches SharedPreferencesAsyncPlatform.instance in
  // its constructor), so the platform is installed once up front and cleared
  // between tests instead of swapped per test.
  final store = InMemorySharedPreferencesAsync.withData({});

  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance = store;
  });

  setUp(() async {
    await store.clear(
      const ClearPreferencesParameters(filter: PreferencesFilters()),
      const SharedPreferencesOptions(),
    );
  });

  group('Frigate disclosure records (D7)', () {
    test('append-only: records accumulate in order and are never rewritten',
        () async {
      final repo = WalletRepository.instance;

      expect(await repo.readFrigateDisclosureRecords(), isEmpty);

      await repo.appendFrigateDisclosureRecord(
          url: 'ssl://frigate1.example:50002', visibility: 'public');
      await repo.appendFrigateDisclosureRecord(
          url: 'frigate2.example:50001', visibility: 'private');
      await repo.appendFrigateDisclosureRecord(
          url: 'ssl://frigate1.example:50002', visibility: 'public');

      final records = await repo.readFrigateDisclosureRecords();
      expect(records.length, 3);
      expect(records[0]['url'], 'ssl://frigate1.example:50002');
      expect(records[0]['visibility'], 'public');
      expect(records[1]['url'], 'frigate2.example:50001');
      expect(records[1]['visibility'], 'private');
      // The repeat URL appends; nothing was deduplicated away or rewritten.
      expect(records[2]['url'], 'ssl://frigate1.example:50002');
    });

    test('every record carries an ISO8601 UTC date', () async {
      final repo = WalletRepository.instance;
      await repo.appendFrigateDisclosureRecord(
          url: 'b:1', visibility: 'private');

      final records = await repo.readFrigateDisclosureRecords();
      final date = DateTime.parse(records.single['date']!);
      expect(date.isUtc, true);
      expect(date.isBefore(DateTime.now().toUtc()), true);
    });

    test('records survive unrelated writes and an empty start', () async {
      final repo = WalletRepository.instance;
      expect(await repo.readFrigateDisclosureRecords(), isEmpty);

      // Unrelated wallet writes must not disturb the record list.
      await repo.saveLastSync(800001);
      expect(await repo.readFrigateDisclosureRecords(), isEmpty);
      expect(await repo.readLastSync(), 800001);
    });
  });

  group('Public warning flag (D6)', () {
    test('starts false and flips exactly once (one-way)', () async {
      final repo = WalletRepository.instance;
      expect(await repo.readFrigatePublicWarned(), false);

      await repo.markFrigatePublicWarned();
      expect(await repo.readFrigatePublicWarned(), true);

      // Marking again changes nothing — the dialog never re-fires (D7).
      await repo.markFrigatePublicWarned();
      expect(await repo.readFrigatePublicWarned(), true);
    });
  });
}
