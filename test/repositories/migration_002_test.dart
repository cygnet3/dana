import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// SQL kept in sync with assets/sql/migrations/002_canonicalize_uppercase_payment_codes.sql
const _migration = '''
  UPDATE tx_recipients
  SET payment_code = lower(payment_code)
  WHERE payment_code = upper(payment_code)
    AND (payment_code LIKE 'SP1%'
      OR payment_code LIKE 'TSP1%'
      OR payment_code LIKE 'SPRT1%'
      OR payment_code LIKE 'BC1%'
      OR payment_code LIKE 'TB1%'
      OR payment_code LIKE 'BCRT1%')
''';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('migration 002 - canonicalize uppercase payment codes in tx_recipients',
      () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE tx_recipients (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transaction_id INTEGER NOT NULL,
          payment_code TEXT NOT NULL,
          amount_sat INTEGER NOT NULL
        )
      ''');
    });

    tearDown(() async => db.close());

    Future<void> insert(String code) => db.insert('tx_recipients', {
          'transaction_id': 1,
          'payment_code': code,
          'amount_sat': 1000,
        });

    Future<List<String>> allCodes() async {
      final rows = await db.query('tx_recipients', columns: ['payment_code']);
      return rows.map((r) => r['payment_code'] as String).toList();
    }

    Future<void> runMigration() => db.execute(_migration);

    group('lowercases all-uppercase addresses', () {
      test('SP mainnet (SP1...)', () async {
        await insert('SP1QABC');
        await runMigration();
        expect(await allCodes(), ['sp1qabc']);
      });

      test('SP testnet (TSP1...)', () async {
        await insert('TSP1QABC');
        await runMigration();
        expect(await allCodes(), ['tsp1qabc']);
      });

      test('SP regtest (SPRT1...)', () async {
        await insert('SPRT1QABC');
        await runMigration();
        expect(await allCodes(), ['sprt1qabc']);
      });

      test('bech32 mainnet (BC1...)', () async {
        await insert('BC1QABC');
        await runMigration();
        expect(await allCodes(), ['bc1qabc']);
      });

      test('bech32 testnet/signet (TB1...)', () async {
        await insert('TB1QABC');
        await runMigration();
        expect(await allCodes(), ['tb1qabc']);
      });

      test('bech32 regtest (BCRT1...)', () async {
        await insert('BCRT1QABC');
        await runMigration();
        expect(await allCodes(), ['bcrt1qabc']);
      });
    });

    group('leaves untouched', () {
      test('already-lowercase SP address', () async {
        await insert('sp1qabc');
        await runMigration();
        expect(await allCodes(), ['sp1qabc']);
      });

      test('already-lowercase bech32 address', () async {
        await insert('bc1qabc');
        await runMigration();
        expect(await allCodes(), ['bc1qabc']);
      });

      test('mixed-case address (not all-uppercase)', () async {
        await insert('Sp1QaBcDeF');
        await runMigration();
        expect(await allCodes(), ['Sp1QaBcDeF']);
      });

      test('Base58 mainnet address (starts with 1)', () async {
        await insert('1A1zP1eP5QGefi2DMPTfTL5SLmv7Divf');
        await runMigration();
        expect(await allCodes(), ['1A1zP1eP5QGefi2DMPTfTL5SLmv7Divf']);
      });

      test('Base58 P2SH address (starts with 3)', () async {
        await insert('3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy');
        await runMigration();
        expect(await allCodes(), ['3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy']);
      });
    });

    test('handles a mixed batch correctly', () async {
      await insert('SP1QUPPER');
      await insert('sp1qlower');
      await insert('BC1QUPPER');
      await insert('1Base58Mixed');

      await runMigration();

      final codes = await allCodes();
      expect(codes, containsAll(['sp1qupper', 'sp1qlower', 'bc1qupper', '1Base58Mixed']));
      expect(codes, isNot(contains('SP1QUPPER')));
      expect(codes, isNot(contains('BC1QUPPER')));
    });
  });
}
