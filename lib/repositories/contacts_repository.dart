import 'package:danawallet/data/models/contact_field.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/repositories/database_helper.dart';
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

  Future<Contact?> getContactByBip353Address(String bip353Address,
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

  Future<Contact?> getContactByPaymentCode(String paymentCode,
      {bool loadCustomFields = false}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'contacts',
      where: 'paymentCode = ?',
      whereArgs: [paymentCode],
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
    final maps = await db.query(
      'contacts',
      orderBy: 'name COLLATE NOCASE ASC',
    );

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
