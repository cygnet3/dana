import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/contact_field.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';

class ContactsRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // private constructor
  ContactsRepository._();

  // singleton instance
  static final instance = ContactsRepository._();

  // Helper method to load custom fields for a contact
  Future<Contact> _loadCustomFields(Contact contact) async {
    if (contact.id == null) return contact;

    final customFields = await getContactFields(contact.id!);
    return Contact(
      id: contact.id,
      name: contact.name,
      bip353Address: contact.bip353Address,
      paymentCode: contact.paymentCode,
      customFields: customFields,
    );
  }

  Future<int> insertContact(Contact contact) async {
    final db = await _dbHelper.database;
    try {
      return await db.insert(
        'contacts',
        contact.toMap(),
        conflictAlgorithm: ConflictAlgorithm.fail,
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw Exception(
            'Contact already exists with this dana address or silent payment address');
      }
      rethrow;
    }
  }

  Future<Contact?> getContact(int id, {bool loadCustomFields = false}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;

    final contact = Contact.fromMap(maps.first);

    if (loadCustomFields) {
      return await _loadCustomFields(contact);
    }

    return contact;
  }

  Future<Contact?> getContactByBip353Address(Bip353Address bip353Address,
      {bool loadCustomFields = false}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'contacts',
      where: 'bip353Address = ?',
      whereArgs: [bip353Address],
    );

    if (maps.isEmpty) return null;

    final contact = Contact.fromMap(maps.first);

    if (loadCustomFields) {
      return await _loadCustomFields(contact);
    }

    return contact;
  }

  Future<List<Contact>> getAllContacts({required bool loadCustomFields}) async {
    final db = await _dbHelper.database;
    var maps = await db.query(
      'contacts',
      orderBy: 'name COLLATE NOCASE ASC',
    );

    try {
      if (await _collapseDuplicatePaymentCodes(db, maps)) {
        maps = await db.query(
          'contacts',
          orderBy: 'name COLLATE NOCASE ASC',
        );
      }
    } catch (e) {
      Logger().e('Failed to collapse duplicate payment codes: $e');
    }

    if (!loadCustomFields) {
      return maps.map((map) => Contact.fromMap(map)).toList();
    }

    // Load custom fields for all contacts
    final contacts = <Contact>[];
    for (var map in maps) {
      final contact = Contact.fromMap(map);
      contacts.add(await _loadCustomFields(contact));
    }

    return contacts;
  }

  /// Rewrites a lone non-canonical payment code in place. Rows that parse to
  /// the same code are deleted and replaced by one contact. Returns true when
  /// a row was written.
  ///
  /// Name and Dana address come from the lowest id that has one. A custom
  /// field type is kept from the lowest id with a non-empty value for it.
  Future<bool> _collapseDuplicatePaymentCodes(
    Database db,
    List<Map<String, Object?>> maps,
  ) async {
    final groups = <String, List<Map<String, Object?>>>{};
    for (final map in maps) {
      final canonical = Contact.fromMap(map).paymentCode.encode();
      (groups[canonical] ??= []).add(map);
    }

    final dirty = groups.entries.where((entry) {
      final rows = entry.value;
      if (rows.length > 1) return true;
      final raw = (rows.single['paymentCode'] as String).trim();
      return raw != entry.key;
    }).toList();
    if (dirty.isEmpty) return false;

    await db.transaction((txn) async {
      for (final entry in dirty) {
        await _collapsePaymentCodeGroup(txn, entry.key, entry.value);
      }
    });
    return true;
  }

  Future<void> _collapsePaymentCodeGroup(
    Transaction txn,
    String canonical,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.length == 1) {
      await txn.update(
        'contacts',
        {'paymentCode': canonical},
        where: 'id = ?',
        whereArgs: [rows.single['id']],
      );
      return;
    }

    final ordered = [...rows]
      ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    final fields = await _fieldsKeptFromLowestId(txn, ordered);

    for (final row in ordered) {
      await txn.delete(
        'contacts',
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    final newId = await txn.insert('contacts', {
      'name': _firstFilled(ordered, 'name'),
      'bip353Address': _firstFilled(ordered, 'bip353Address'),
      'paymentCode': canonical,
    });
    for (final field in fields) {
      await txn.insert('contact_fields', {
        'contact_id': newId,
        'field_type': field['field_type'],
        'field_value': field['field_value'],
      });
    }

    Logger().i(
        'Collapsed contacts ${ordered.map((row) => row['id']).join(', ')} into id=$newId');
  }

  String? _firstFilled(List<Map<String, Object?>> orderedRows, String column) {
    for (final row in orderedRows) {
      final value = row[column] as String?;
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return orderedRows.first[column] as String?;
  }

  /// Field type is the key. Values come from the lowest id with a non-empty
  /// value for that type. An empty value does not block a later row.
  Future<List<Map<String, Object?>>> _fieldsKeptFromLowestId(
    Transaction txn,
    List<Map<String, Object?>> orderedRows,
  ) async {
    final kept = <Map<String, Object?>>[];
    final empties = <String, List<Map<String, Object?>>>{};
    final takenTypes = <String>{};
    for (final row in orderedRows) {
      final rowFields = await txn.query(
        'contact_fields',
        where: 'contact_id = ?',
        whereArgs: [row['id']],
        orderBy: 'id ASC',
      );
      final filledOnThisRow = <String>{};
      for (final field in rowFields) {
        final type = field['field_type'] as String;
        if (takenTypes.contains(type)) continue;
        final value = field['field_value'] as String?;
        if (value == null || value.trim().isEmpty) {
          if (filledOnThisRow.contains(type) || empties.containsKey(type)) {
            continue;
          }
          empties[type] = [field];
          continue;
        }
        empties.remove(type);
        filledOnThisRow.add(type);
        kept.add(field);
      }
      takenTypes.addAll(filledOnThisRow);
    }
    for (final fields in empties.values) {
      kept.addAll(fields);
    }
    return kept;
  }

  Future<int> updateContact(Contact contact) async {
    final db = await _dbHelper.database;
    try {
      return await db.update(
        'contacts',
        contact.toMap(),
        where: 'id = ?',
        whereArgs: [contact.id],
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw Exception(
            'Another contact already exists with this dana address or silent payment address');
      }
      rethrow;
    }
  }

  Future<int> deleteContact(int id) async {
    final db = await _dbHelper.database;
    // Custom fields will be deleted automatically due to CASCADE
    return await db.delete(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllContacts() async {
    final db = await _dbHelper.database;
    // Custom fields will be deleted automatically due to CASCADE
    return await db.delete('contacts');
  }

  Future<int> getContactCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM contacts');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Contact Fields CRUD operations
  Future<int> insertContactField(ContactField field) async {
    final db = await _dbHelper.database;
    return await db.insert(
      'contact_fields',
      field.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ContactField>> getContactFields(int contactId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'contact_fields',
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'field_type ASC, id ASC',
    );

    return maps.map((map) => ContactField.fromMap(map)).toList();
  }

  Future<ContactField?> getContactField(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'contact_fields',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return ContactField.fromMap(maps.first);
  }

  Future<List<ContactField>> getContactFieldsByType(
    int contactId,
    String fieldType,
  ) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'contact_fields',
      where: 'contact_id = ? AND field_type = ?',
      whereArgs: [contactId, fieldType],
      orderBy: 'id ASC',
    );

    return maps.map((map) => ContactField.fromMap(map)).toList();
  }

  Future<int> updateContactField(ContactField field) async {
    final db = await _dbHelper.database;
    return await db.update(
      'contact_fields',
      field.toMap(),
      where: 'id = ?',
      whereArgs: [field.id],
    );
  }

  Future<int> deleteContactField(int id) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'contact_fields',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteContactFields(int contactId) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'contact_fields',
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );
  }
}
