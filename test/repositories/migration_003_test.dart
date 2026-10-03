import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p show basename, join;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tests for migration `003_contacts_nocase_collation.sql` — cygnet3/dana#480.
///
/// Harness mirrors `test/repositories/migration_002_test.dart` (sqflite FFI)
/// but drives the *real* upgrade path: the database is created at the base
/// version and reopened at the next one so `onUpgrade` runs exactly the new
/// migration — the same way `DatabaseHelper._initDB` / `_performMigrations`
/// do in production: discovery under `assets/sql/migrations`, alphabetical
/// order, `version == number of migration files`, statements split on ';',
/// and `PRAGMA foreign_keys = ON` from `_onConfigure`.
///
/// The SQL is read from the real asset file and never inlined, so the
/// shipped migration and its test cannot silently diverge.

final Directory _migrationsDir =
    Directory(p.join('assets', 'sql', 'migrations'));

const String _migration003 = '003_contacts_nocase_collation.sql';

/// Same discovery + ordering rule as `DatabaseHelper._initDB`.
List<String> discoverMigrations() => (_migrationsDir
    .listSync(followLinks: false)
    .map((e) => p.basename(e.path))
    .where((name) => RegExp(r'^\d{3}_.+\.sql$').hasMatch(name))
    .toList()
  ..sort());

/// Same execution as `DatabaseHelper._performMigrations`: split on ';' and
/// execute each trimmed non-empty statement. Accepts a Database or the
/// Transaction handed to it by sqflite's versioned open.
Future<void> runMigrationFiles(Object executor, List<String> files) async {
  for (final fileName in files) {
    final sql =
        await File(p.join(_migrationsDir.path, fileName)).readAsString();
    for (final statement
        in sql.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      if (executor is Transaction) {
        await executor.execute(statement);
      } else {
        await (executor as Database).execute(statement);
      }
    }
  }
}

Future<void> _configure(Object db) async =>
    // Same pragma as DatabaseHelper._onConfigure — this is what makes the
    // DROP/reNAME of the rebuild observable through ON DELETE CASCADE.
    (db as Database).execute('PRAGMA foreign_keys = ON');

/// Opens (or upgrades) a database exactly like DatabaseHelper does: version
/// equals the number of discovered migration assets, and onUpgrade replays
/// the not-yet-applied ones in file-name order.
Future<Database> openVersioned(String path, int version) => openDatabase(
      path,
      version: version,
      onConfigure: _configure,
      onUpgrade: (db, oldVersion, newVersion) => runMigrationFiles(
          db, discoverMigrations().sublist(oldVersion, newVersion)),
    );

/// The version book is DERIVED, never typed: `DatabaseHelper._initDB` sets
/// `version = migrations.length`, so a literal that lags the file count makes
/// `sublist` skip the newest migration — the upgrade then silently does not
/// happen and every post-fix assertion below would pass or fail on the wrong
/// schema. Both numbers therefore come off the discovered list.
int get _headVersion => discoverMigrations().length;

/// The book as it stood at pin 636d1e6d, i.e. before 003 landed.
int get _pinVersion => _headVersion - 1;

/// One named in-memory database per call.
///
/// A relative name is not in memory: `fixPath` joins it onto
/// `.dart_tool/sqflite_common_ffi/databases/`. A counter that restarts at 0
/// is not unique across runs either — the next `flutter test` process mints
/// the same names and reopens those files. A `file:` URI skips that join.
/// `mode=memory&cache=shared` is a named in-memory database (the form
/// sqflite's own connection tracker uses); `cache=shared` is what makes a
/// later open of the same path, which the per-path connection cache may do,
/// see this database instead of an empty private one. [_runNonce] keeps a
/// later process from minting the same names.
final String _runNonce =
    '$pid-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
int _pathSeq = 0;
String _freshPath(String tag) =>
    'file:$tag-$_runNonce-${++_pathSeq}?mode=memory&cache=shared';

// One seed, and every "case variant" below is DERIVED from it. A hand-typed
// twin silently drifts into an unrelated code, and then a case-insensitive
// uniqueness assertion proves nothing — so the pair is computed, not copied.
const String _codeSeed = 'sp1qabcdefghij0123456789abcdefghijklmnopqrstuvexyz';
const String _codeLower = _codeSeed;
final String _codeUpper = _codeSeed.toUpperCase();

/// A third spelling of the very same code: neither all-lower nor all-upper,
/// the shape the old code[0]/code[1] heuristic let through.
final String _codeMixed = List<String>.generate(_codeSeed.length, (i) {
  final c = _codeSeed[i];
  return i % 2 == 0 ? c.toUpperCase() : c;
}).join();

final Matcher _isUniqueConstraintError = _UniqueConstraintErrorMatcher();

class _UniqueConstraintErrorMatcher extends Matcher {
  @override
  bool matches(Object? item, [Map? matchState]) =>
      item is DatabaseException && item.isUniqueConstraintError();

  @override
  Description describe(Description description) => description
      .add('a DatabaseException reporting a UNIQUE constraint violation');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Contract of the fixtures themselves: if these do not hold, every
    // case-insensitivity assertion below is vacuous — it would be comparing
    // two genuinely different addresses and still report a clean run.
    expect(_codeLower, isNot(equals(_codeUpper)),
        reason: 'the pair must actually differ in case');
    expect(_codeLower.toUpperCase(), equals(_codeUpper),
        reason: 'the pair must be the very same code in two spellings');
    expect(_codeUpper.toLowerCase(), equals(_codeLower),
        reason: 'and the fold must be symmetric');
    expect(_codeMixed, isNot(anyOf(equals(_codeLower), equals(_codeUpper))),
        reason: 'a third spelling must exist to expose heuristic blind spots');
    expect(_codeMixed.toUpperCase(), equals(_codeUpper),
        reason: 'yet fold onto the same canonical code');
  });

  test('a fresh path is an in-memory database under a per-run name', () async {
    final path = _freshPath('dana-003-mem');
    expect(path, startsWith('file:'));
    expect(path, contains('mode=memory'));
    expect(path, contains('$pid-'),
        reason: 'a counter that restarts at 0 repeats the same names next run');
    final db = await openVersioned(path, _pinVersion);
    addTearDown(() => db.close());
    // An on-disk database reports its file here; an in-memory one reports ''.
    expect((await db.rawQuery('PRAGMA database_list')).single['file'], '');
  });

  group('migration discovery and runner contract', () {
    test('003 is discovered by the 00N_ rule and sorts last (version book)',
        () {
      final found = discoverMigrations();
      expect(found, contains(_migration003),
          reason: 'assets/sql/migrations must ship the 003 migration');
      expect(found.indexOf(_migration003), found.length - 1,
          reason: 'it must sort last so the version book only ever appends');
    });

    test(
        'the 003 file declares its keys with COLLATE NOCASE and keeps every '
        'statement free of a ";" outside a terminator (the runner splits on it)',
        () {
      final sql =
          File(p.join(_migrationsDir.path, _migration003)).readAsStringSync();
      expect(sql, contains('COLLATE NOCASE'),
          reason: 'bare `UNIQUE NOCASE` is a SQLite syntax error; NOCASE is '
              'legal only after the COLLATE keyword');
      for (final line in sql.split('\n')) {
        final commentIndex = line.indexOf('--');
        if (commentIndex >= 0) {
          expect(line.substring(commentIndex).contains(';'), isFalse,
              reason: 'the runner splits blindly on ";" and would cut this '
                  'comment apart: $line');
        }
      }
    });
  });

  group(
      '(a) REPRODUCTION at the base schema (the pin book 000 + 001 + 002, '
      'BINARY collation) — the state shipped at pin 636d1e6d', () {
    late Database db;
    // Each test gets its OWN database: the FFI factory caches a connection per
    // path, so a shared in-memory path would hand a later group the schema an
    // earlier one left behind.
    setUp(() async =>
        db = await openVersioned(_freshPath('dana-003-repro'), _pinVersion));
    tearDown(() => db.close());

    Future<void> seedLegacyCaseTwins() async {
      // 41 was stored before sanitizePaymentCode() existed, 42 after it.
      await db.insert(
          'contacts', {'id': 41, 'name': 'alice', 'paymentCode': _codeUpper});
      await db.insert('contacts',
          {'id': 42, 'name': 'alice too', 'paymentCode': _codeLower});
    }

    test('a case-variant pair coexists: one payment code, two contacts',
        () async {
      await seedLegacyCaseTwins();
      final rows = await db.query('contacts', orderBy: 'id');
      expect(rows.length, 2,
          reason: 'BINARY collation stores the twins as two distinct keys');
      expect(rows.map((r) => r['paymentCode']), [_codeUpper, _codeLower]);
    });

    test(
        'a checkUpperCases-style pass with the UNIQUE collision swallowed keeps '
        'both rows and leaves the uppercase row non-canonical', () async {
      await seedLegacyCaseTwins();
      await db.insert('contact_fields',
          {'contact_id': 41, 'field_type': 'email', 'field_value': 'a@b.c'});

      Object? swallowed;
      try {
        // What ContactsState.checkUpperCases does for row 41: canonicalize
        // and update. The repository turns the DatabaseException into a
        // user-facing Exception which the state layer logs and swallows.
        await db.update(
          'contacts',
          {'id': 41, 'name': 'alice', 'paymentCode': _codeLower},
          where: 'id = ?',
          whereArgs: [41],
        );
      } on DatabaseException catch (e) {
        swallowed = e;
      }

      expect(swallowed, isNotNull,
          reason: 'canonicalizing 41 collides with the lowercase row 42');
      expect(swallowed, _isUniqueConstraintError);

      final rows = await db.query('contacts', orderBy: 'id');
      expect(rows.length, 2, reason: 'the pair is never reconciled');
      expect(rows.map((r) => r['paymentCode']), [_codeUpper, _codeLower],
          reason: 'row 41 keeps its non-canonical uppercase spelling forever');

      final byLower = await db
          .query('contacts', where: 'paymentCode = ?', whereArgs: [_codeLower]);
      expect(byLower.length, 1,
          reason: 'the case-sensitive lookup matches only the lowercase twin');
      expect(byLower.single['id'], 42);
    });

    test(
        'the base schema accepts a NEW uppercase twin of an existing lowercase '
        'payment code — the invariant the fix must establish is absent',
        () async {
      await db.insert(
          'contacts', {'id': 51, 'name': 'bob', 'paymentCode': _codeLower});
      await db.insert('contacts',
          {'id': 52, 'name': 'bob upper', 'paymentCode': _codeUpper});
      final rows =
          await db.query('contacts', where: 'id >= ?', whereArgs: [51]);
      expect(rows.length, 2,
          reason: 'RED pre-fix: BINARY UNIQUE lets the case twin through');
    });
  });

  group('(b) POST-FIX invariant — upgrading the base schema through 003', () {
    late Directory tmp;
    late String dbPath;
    late Database db;

    Future<Database> openBase() => openVersioned(dbPath, _pinVersion);

    /// A PRIVATE base-pin file for the tests that must seed legacy rows: the
    /// group's setUp already migrated dbPath through 003, so reopening it at
    /// the base version would hand back the migrated NOCASE schema (a downgrade
    /// runs nothing) and the twin pair could never coexist to begin with.
    Future<({Database base, String path})> freshBasePin() async {
      final dir = Directory.systemTemp.createTempSync('dana-003-base');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'dana.db');
      return (base: await openVersioned(path, _pinVersion), path: path);
    }

    Future<Database> openMigrating(String path) => openDatabase(
          path,
          version: _headVersion,
          onConfigure: _configure,
          onUpgrade: (db, oldVersion, newVersion) {
            expect(oldVersion, _pinVersion);
            expect(newVersion, _headVersion);
            return runMigrationFiles(db, [_migration003]);
          },
        );

    Future<Database> openMigrated() => openMigrating(dbPath);

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('dana-003-post');
      dbPath = p.join(tmp.path, 'dana.db');
      // Fresh install at the base pin, then the app ships 003.
      await (await openBase()).close();
      db = await openMigrated();
    });

    tearDown(() async {
      try {
        await db.close();
      } catch (_) {/* already closed */}
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException catch (_) {/* already gone */}
    });

    test(
        'inserting the uppercase twin of an existing lowercase code is rejected',
        () async {
      await db.insert(
          'contacts', {'id': 61, 'name': 'carol', 'paymentCode': _codeLower});
      await expectLater(
          db.insert('contacts',
              {'id': 62, 'name': 'carol again', 'paymentCode': _codeUpper},
              conflictAlgorithm: ConflictAlgorithm.fail),
          throwsA(_isUniqueConstraintError));

      final rows =
          await db.query('contacts', where: 'id >= ?', whereArgs: [61]);
      expect(rows.length, 1, reason: 'the twin never reaches storage');
      expect(rows.single['paymentCode'], _codeLower,
          reason: 'first writer wins and keeps its spelling');
    });

    test('getContactByPaymentCode matches case-insensitively', () async {
      await db.insert(
          'contacts', {'id': 71, 'name': 'dave', 'paymentCode': _codeLower});
      for (final probe in [_codeLower, _codeUpper]) {
        final rows = await db
            .query('contacts', where: 'paymentCode = ?', whereArgs: [probe]);
        expect(rows.length, 1,
            reason: 'the repository query must hit the row whatever the case');
        expect(rows.single['id'], 71);
      }
    });

    test('a legacy case-variant pair is merged onto its oldest row', () async {
      await db.close();
      final seeded = await freshBasePin();
      await seeded.base.insert(
          'contacts', {'id': 41, 'name': 'alice', 'paymentCode': _codeUpper});
      await seeded.base.insert('contacts',
          {'id': 42, 'name': 'alice too', 'paymentCode': _codeLower});
      await seeded.base.insert('contact_fields',
          {'contact_id': 41, 'field_type': 'email', 'field_value': 'a@b.c'});
      await seeded.base.insert('contact_fields',
          {'contact_id': 42, 'field_type': 'phone', 'field_value': '123'});
      await seeded.base.close();

      db = await openMigrating(seeded.path);

      final rows = await db.query('contacts', orderBy: 'id');
      expect(rows.length, 1, reason: 'the pair collapsed to one contact');
      expect(rows.single['id'], 41, reason: 'MIN(id) — the oldest row wins');
      expect(rows.single['name'], 'alice');

      final fields = await db.query('contact_fields', orderBy: 'id');
      expect(fields.length, 2,
          reason: 'EXPLICIT DECISION: the loser fields are re-attached to the '
              'winner, they are never cascade-deleted with the loser');
      expect(fields.map((f) => f['contact_id']), everyElement(equals(41)));
      expect(
          fields.map((f) => f['field_value']), containsAll(['a@b.c', '123']));

      final orphans = await db.rawQuery('''
          SELECT COUNT(*) AS n FROM contact_fields
          WHERE contact_id NOT IN (SELECT id FROM contacts)
        ''');
      expect(orphans.single['n'], 0,
          reason: 'no orphaned custom field survives the rebuild');
    });

    test('non-colliding contacts and their fields are carried over untouched',
        () async {
      await db.close();
      final seeded = await freshBasePin();
      await seeded.base.insert(
          'contacts', {'id': 1, 'name': 'erin', 'paymentCode': _codeLower});
      await seeded.base.insert('contacts',
          {'id': 2, 'name': 'frank', 'paymentCode': 'sp1anotherdifferentcode'});
      await seeded.base.insert('contact_fields',
          {'contact_id': 1, 'field_type': 'email', 'field_value': 'e@f.g'});
      await seeded.base.insert('contact_fields',
          {'contact_id': 2, 'field_type': 'telegram', 'field_value': 'hh'});
      await seeded.base.close();

      db = await openMigrating(seeded.path);

      expect((await db.query('contacts', orderBy: 'id')).map((c) => c['name']),
          ['erin', 'frank']);
      final kept = await db.query('contact_fields', orderBy: 'id');
      expect(kept.map((f) => f['contact_id']), [1, 2]);
      expect(kept.map((f) => f['field_value']), ['e@f.g', 'hh']);
    });

    test('the rebuilt foreign key stays live: ON DELETE CASCADE still fires',
        () async {
      await db.insert(
          'contacts', {'id': 81, 'name': 'gina', 'paymentCode': 'sp1ginacode'});
      await db.insert('contact_fields',
          {'contact_id': 81, 'field_type': 'email', 'field_value': 'g@h.i'});
      expect(await db.query('contact_fields'), hasLength(1));

      await db.delete('contacts', where: 'id = ?', whereArgs: [81]);

      expect(await db.query('contact_fields'), isEmpty,
          reason: 'the rebuilt child must keep the cascade definition of 000');
    });

    test(
        'the schema declares both keys COLLATE NOCASE and the 000 indexes return',
        () async {
      final ddl = await db.query('sqlite_master',
          columns: ['name', 'sql'],
          where: "type IN ('table','index') "
              "AND tbl_name IN ('contacts','contact_fields') AND sql IS NOT NULL",
          orderBy: 'name');
      final byName = {
        for (final r in ddl) r['name'] as String: r['sql'] as String
      };
      expect(
          byName.keys,
          containsAll([
            'contacts',
            'contact_fields',
            'idx_contacts_bip353_address',
            'idx_contacts_payment_code',
            'idx_contact_fields_contact_id',
          ]),
          reason: 'the rebuild must not silently drop an index of 000');
      expect(byName['contacts'], contains('COLLATE NOCASE'));
      expect(byName['contact_fields'], contains('ON DELETE CASCADE'));
      expect(byName['contact_fields'], isNot(contains('contacts_new')),
          reason: 'ALTER TABLE RENAME must rewrite the parent reference');
    });

    test('foreign key integrity is clean after the rebuild', () async {
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty,
          reason: 'the rebuild may not leave an FK violation behind');
    });

    test('the migration is idempotent when re-applied to the migrated schema',
        () async {
      await db.insert(
          'contacts', {'id': 91, 'name': 'gina', 'paymentCode': 'sp1ginacode'});
      await db.insert('contact_fields',
          {'contact_id': 91, 'field_type': 'email', 'field_value': 'g@h.i'});

      await db.transaction((txn) => runMigrationFiles(txn, [_migration003]));

      expect((await db.query('contacts', orderBy: 'id')).map((c) => c['name']),
          ['gina']);
      expect(
          (await db.query('contact_fields', orderBy: 'id'))
              .map((f) => f['field_value']),
          ['g@h.i']);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  });

  group('(c) fresh install at the current schema version', () {
    late Database db;

    // A brand-new database at the HEAD of the version book — production opens
    // exactly this schema, so the book number must come off the discovered
    // files: asking for a stale literal here would replay one migration short
    // and the "the schema itself refuses the twin" assertions below would then
    // run against the pre-003 BINARY table and mean nothing.
    setUp(() async =>
        db = await openVersioned(_freshPath('dana-003-head'), _headVersion));
    tearDown(() => db.close());

    test('a case-variant pair can never be inserted, in either spelling',
        () async {
      await db.insert(
          'contacts', {'id': 1, 'name': 'hal', 'paymentCode': _codeLower});
      for (final twin in [_codeUpper, _codeMixed]) {
        await expectLater(
            db.insert(
                'contacts', {'id': 2, 'name': 'hal twin', 'paymentCode': twin},
                conflictAlgorithm: ConflictAlgorithm.fail),
            throwsA(_isUniqueConstraintError),
            reason: 'the schema itself must refuse the case twin: $twin');
      }
    });

    test('AUTOINCREMENT keeps handing out fresh ids after the rebuild',
        () async {
      await db.insert(
          'contacts', {'id': 41, 'name': 'ia', 'paymentCode': 'sp1iatestcode'});
      final id = await db
          .insert('contacts', {'name': 'ib', 'paymentCode': 'sp1bobtestcode'});
      expect(id, greaterThan(41),
          reason: 'the copied explicit ids must not make the counter collide');
    });
  });

  group('(d) why the shipped migration rebuilds BOTH tables', () {
    test(
        'the single-table rebuild drafted in the issue would cascade away every '
        'custom field — guarded against', () async {
      final db = await openVersioned(_freshPath('dana-003-draft'), _pinVersion);
      addTearDown(() => db.close());
      await db.insert(
          'contacts', {'id': 91, 'name': 'henrik', 'paymentCode': _codeLower});
      await db.insert('contact_fields',
          {'contact_id': 91, 'field_type': 'email', 'field_value': 'h@i.j'});

      // Exactly the draft printed in cygnet3/dana#480: rebuild the parent only.
      await db.transaction((txn) async {
        await txn.execute('''
            CREATE TABLE contacts_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT,
              bip353Address TEXT UNIQUE COLLATE NOCASE,
              paymentCode TEXT NOT NULL UNIQUE COLLATE NOCASE
            )
          ''');
        await txn.execute(
            'INSERT INTO contacts_new (id, name, bip353Address, paymentCode) '
            'SELECT id, name, bip353Address, paymentCode FROM contacts '
            'WHERE id IN (SELECT MIN(id) FROM contacts GROUP BY paymentCode COLLATE NOCASE)');
        await txn.execute('DROP TABLE contacts');
        await txn.execute('ALTER TABLE contacts_new RENAME TO contacts');
      });

      expect(await db.query('contact_fields'), isEmpty,
          reason: 'DROP TABLE of the parent fires ON DELETE CASCADE into the '
              'untouched child — this is why the shipped migration rebuilds '
              'contact_fields as well and re-attaches before removing duplicates');
    });
  });
  group(
      '(e) the survivor is canonicalized and its identity rescued — the '
      'scenario of cygnet3/dana#480 as stated by the reviewer: a v0.8.x install '
      'registered the same destination twice, once lower and once upper, in an '
      'UNKNOWN order', () {
    Future<Database> migrateSeeded(List<List<Object?>> contacts,
        [List<List<Object?>> fields = const []]) async {
      final dir = Directory.systemTemp.createTempSync('dana-003-fold');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'dana.db');
      final base = await openVersioned(path, _pinVersion);
      for (final c in contacts) {
        await base.insert(
            'contacts',
            {
              'id': c[0],
              'name': c[1],
              'bip353Address': c[2],
              'paymentCode': c[3],
            },
            conflictAlgorithm: ConflictAlgorithm.fail);
      }
      for (final f in fields) {
        await base.insert('contact_fields',
            {'contact_id': f[0], 'field_type': f[1], 'field_value': f[2]});
      }
      await base.close();
      return openDatabase(path,
          version: _headVersion,
          onConfigure: _configure,
          onUpgrade: (db, oldV, newV) =>
              runMigrationFiles(db, [_migration003]));
    }

    Future<List<List<Object?>>> contactsOf(Database db) => db
        .query('contacts',
            columns: ['id', 'name', 'bip353Address', 'paymentCode'],
            orderBy: 'id')
        .then((rs) => rs
            .map((r) =>
                [r['id'], r['name'], r['bip353Address'], r['paymentCode']])
            .toList());

    // The fold is what makes the survivor usable WHATEVER the seeding order, so
    // both orders must be asserted: MIN(id) elects by AGE and the two spellings
    // were entered in an order nobody knows, so the row that stays is just as
    // likely to be the bare legacy one as the canonical one.
    test(
        'the LOWERCASE contact was saved first: survivor 41 is already canonical',
        () async {
      final db = await migrateSeeded([
        [41, 'alice', 'alice@dana.example', _codeLower],
        [42, 'alice too', null, _codeUpper],
      ]);
      expect(
          await contactsOf(db),
          [
            [41, 'alice', 'alice@dana.example', _codeLower],
          ],
          reason: 'one row kept, and its key needs no fold');
    });

    test(
        'the UPPERCASE contact was saved first: survivor 41 is folded to lowercase',
        () async {
      final db = await migrateSeeded([
        [41, 'alice', null, _codeUpper],
        [42, 'alice too', 'alice@dana.example', _codeLower],
      ]);
      expect(
          await contactsOf(db),
          [
            [41, 'alice', 'alice@dana.example', _codeLower],
          ],
          reason: 'MIN(id) keeps the legacy row, so the fold to the canonical '
              'spelling is the ONLY thing standing between this contact and an '
              'anonymous one: every lookup is case sensitive '
              '(ContactsRepository.getContactByPaymentCode queries paymentCode = ? '
              'and the wallet joins its history onto a contact through it)');
      expect(
          await db.rawQuery(
              'SELECT COUNT(*) AS n FROM contacts WHERE paymentCode <> lower(paymentCode)'),
          [
            {'n': 0}
          ],
          reason: 'no dirty key may survive the rebuild in any row');
    });

    test(
        'a survivor that is bare adopts the name and the address of the doomed twin',
        () async {
      final db = await migrateSeeded([
        [41, null, null, _codeUpper],
        [42, 'alice too', 'alice@dana.example', _codeLower],
      ], [
        [41, 'email', 'a@b.c'],
        [42, 'phone', '123'],
      ]);
      expect(
          await contactsOf(db),
          [
            [41, 'alice too', 'alice@dana.example', _codeLower],
          ],
          reason:
              'the row the user actually saved is the NEWER one; dropping its '
              'identity with the duplicate is the leak the review of the first '
              'draft caught. The custom fields already survived, name and '
              'bip353Address did not');
      final fields = await db.query('contact_fields',
          columns: ['contact_id', 'field_value'], orderBy: 'id');
      expect(fields.map((f) => f['contact_id']), everyElement(equals(41)));
      expect(
          fields.map((f) => f['field_value']), containsAll(['a@b.c', '123']));
    });

    test(
        'values the survivor already owns are never overwritten by the doomed twin',
        () async {
      final db = await migrateSeeded([
        [41, 'alice', 'alice@dana.example', _codeUpper],
        [42, 'alice too', 'someone.else@dana.example', _codeLower],
      ]);
      expect(
          await contactsOf(db),
          [
            [41, 'alice', 'alice@dana.example', _codeLower],
          ],
          reason:
              'the tie-break stays the one this file uses everywhere: oldest '
              'wins, holes are filled. This is why the rescue reads '
              'survivor.name ?: newest.name and not the other way around, which '
              'would also break the (b) group asserting the merged name is alice');
    });

    test(
        'the mixed-case spelling that escapes the all-uppercase probe is folded too',
        () async {
      expect(_codeMixed, isNot(equals(_codeMixed.toUpperCase())),
          reason:
              'checkUpperCases() probes code == code.toUpperCase(), so this '
              'row is never even offered to the sanitizer at runtime');
      final db = await migrateSeeded([
        [41, null, null, _codeMixed],
        [42, 'm', null, _codeLower],
      ]);
      expect(
          await contactsOf(db),
          [
            [41, 'm', null, _codeLower],
          ],
          reason: 'the predicate is paymentCode <> lower(paymentCode), so a '
              'mixed-case spelling is folded the same way as an all-uppercase '
              'one');
    });

    test('an address worn by two DIFFERENT codes does not abort the rebuild',
        () async {
      final db = await migrateSeeded([
        [41, 'x', null, 'sp1aaaa'],
        [42, 'y', 'dup@dana.example', 'sp1bbbb'],
        [43, 'z', 'DUP@dana.example', 'sp1cccc'],
      ]);
      final rows = await contactsOf(db);
      expect(rows.length, 3,
          reason:
              'these are not twins: the deduplication groups on paymentCode, so '
              'nothing collapses them. The rebuilt UNIQUE COLLATE NOCASE on '
              'bip353Address would however refuse two of them, and an abort here '
              'would leave the whole base on the old BINARY schema with every '
              'contact unfindable — so the oldest carrier keeps the label');
      expect(rows[1][2], 'dup@dana.example');
      expect(rows[2][2], isNull, reason: 'the younger carrier gives it up');
    });

    test(
        'an adopted address that clashes with an unrelated contact is released',
        () async {
      final db = await migrateSeeded([
        [41, 'a', null, _codeUpper],
        [42, 'b', 'rescued@dana.example', _codeLower],
        [43, 'c', 'RESCUED@dana.example', 'sp1zzzq'],
      ]);
      final rows = await contactsOf(db);
      expect(rows.length, 2,
          reason: 'the twins collapsed, the stranger stayed');
      expect(rows[0][0], 41);
      expect(rows[0][2], 'rescued@dana.example',
          reason: 'the rescue itself succeeded');
      expect(rows[1][0], 43);
      expect(rows[1][2], isNull,
          reason: 'and the clash it caused is resolved by age, not by abort');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });

    test(
        'a survivor that already holds the colliding address drops the twin\'s '
        'free one', () async {
      final db = await migrateSeeded([
        [10, 'older', 'keep@x', 'sp1other'],
        [41, 'survivor', 'KEEP@x', 'SP1AAA'],
        [42, 'twin', 'unique@x', 'sp1aaa'],
      ]);
      expect(
          await contactsOf(db),
          [
            [10, 'older', 'keep@x', 'sp1other'],
            [41, 'survivor', null, 'sp1aaa'],
          ],
          reason: 'COALESCE keeps KEEP@x because the survivor\'s own address '
              'is non-null, so unique@x is never a candidate. The CASE then '
              'sees id 10 already holds keep@x and stores null');
    });

    test(
        'the newest twin\'s colliding address is chosen over an older twin\'s '
        'free one', () async {
      final db = await migrateSeeded([
        [10, 'older', 'keep@x', 'sp1other'],
        [41, 'survivor', null, 'SP1AAA'],
        [42, 'mid', 'unique@x', 'sp1aaa'],
        [43, 'newest', 'KEEP@x', 'Sp1AAA'],
      ]);
      expect(
          await contactsOf(db),
          [
            [10, 'older', 'keep@x', 'sp1other'],
            [41, 'survivor', null, 'sp1aaa'],
          ],
          reason: 'ORDER BY id DESC LIMIT 1 picks KEEP@x. The CASE nulls it, '
              'and unique@x is never tried');
    });
  });
}
