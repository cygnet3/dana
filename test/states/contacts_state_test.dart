import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/data/models/contact_field.dart';
import 'package:danawallet/exceptions.dart';
import 'package:danawallet/repositories/contacts_repository.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests of the canonicalization pass of ContactsState — cygnet3/dana#480,
/// the runtime half of the fix. The storage half lives in
/// `test/repositories/migration_003_test.dart`.
///
/// The pass is the one piece of the class that speaks to the database, and
/// its production fold comes from the Rust bridge, so nothing could drive it
/// without a device — which is precisely why the merge of a colliding pair
/// had never been covered. Repository and fold are injected here. The store
/// below compares the stored BYTES, the way the table of a v0.8.x install
/// still does before migration 003 gives it COLLATE NOCASE — that is the
/// state this pass exists to repair, and the byte-exact scan is what makes a
/// twin pair observable to it at all.
void main() {
  const codeSeed = 'sp1qabcdefghij0123456789abcdefghijklmnopqrstuvexyz';
  final codeUpper = codeSeed.toUpperCase();
  // The third spelling of the selfsame code: neither all lower nor all upper,
  // the shape every probe so far let through.
  final codeMixed = List<String>.generate(codeSeed.length,
      (i) => i % 2 == 0 ? codeSeed[i].toUpperCase() : codeSeed[i]).join();

  late _Store store;
  late List<String> folded;

  ContactsState buildState() => ContactsState(
        repository: store,
        sanitize: (code) {
          folded.add(code);
          return code.toLowerCase();
        },
      );

  setUp(() {
    store = _Store();
    folded = [];
  });

  group('which stored spellings the pass offers to the fold', () {
    test('an all-uppercase legacy row, as ever', () async {
      store.insert(_contact(41, 'alice', null, codeUpper));
      await buildState().refreshContacts();

      expect(folded, contains(codeUpper));
      expect(store.valueOf(41)['paymentCode'], codeSeed,
          reason: 'the row is folded as it is written back, so the stored '
              'bytes agree with the folded key of the rebuilt table');
      expect(store.deleted, isEmpty,
          reason: 'a single row of a key cannot collide, so no merge follows');
    });

    test('the mixed-case row that escaped both of the earlier probes', () async {
      expect(codeMixed, isNot(equals(codeMixed.toUpperCase())),
          reason: 'a whole-string all-uppercase probe does not see it');
      expect(codeMixed, isNot(equals(codeMixed.toLowerCase())));

      store.insert(_contact(41, 'alice', null, codeMixed));
      await buildState().refreshContacts();

      expect(folded, contains(codeMixed),
          reason: 'the probe is now the inverse of the canonical form, not a '
              'shape of capitals');
      expect(store.valueOf(41)['paymentCode'], codeSeed);
    });

    test('a canonical row is never offered', () async {
      store.insert(_contact(41, 'alice', 'alice@dana.example', codeSeed));
      await buildState().refreshContacts();

      expect(folded, isEmpty);
      expect(store.writes, isEmpty);
    });
  });

  group('the merge of a colliding pair', () {
    test('the list tells the same story as the table: one entry, no twin',
        () async {
      store.insertAll([
        _contact(41, 'alice', null, codeUpper),
        _contact(42, 'alice too', 'alice@dana.example', codeSeed),
      ]);
      store.fields.addAll([
        _row(1, 41, 'email', 'a@b.c'),
        _row(2, 42, 'phone', '123'),
      ]);

      final state = buildState();
      await state.refreshContacts();

      expect(store.deleted, [41]);
      expect(state.getOtherContacts().map((c) => c.id), [42],
          reason: 'the merge appended the survivor while the ordinary pass '
              'still held the selfsame identifier — one contact, twice listed');
      expect(state.getOtherContacts().single.paymentCode, codeSeed);
      expect(store.ownersOf(42), containsAll(['a@b.c', '123']),
          reason: 'both custom fields re-attached to the survivor');
    });

    test('the survivor adopts the identity the doomed row held', () async {
      store.insertAll([
        _contact(41, 'alice too', 'alice@dana.example', codeUpper),
        _contact(42, null, null, codeSeed),
      ]);

      final state = buildState();
      await state.refreshContacts();

      expect(store.deleted, [41]);
      expect(state.getOtherContacts().map((c) => c.id), [42]);
      expect(store.valueOf(42)['name'], 'alice too',
          reason: 'the name the user actually saved would otherwise have been '
              'deleted along with the duplicate');
      expect(store.valueOf(42)['bip353Address'], 'alice@dana.example');
      expect(state.getOtherContacts().single.name, 'alice too',
          reason: 'and the copy in memory agrees with the table');
    });

    test('what the survivor already owns is not overwritten by the doomed one',
        () async {
      store.insertAll([
        _contact(41, 'alice', 'alice@dana.example', codeUpper),
        _contact(42, 'someone else', 'other@dana.example', codeSeed),
      ]);

      await buildState().refreshContacts();

      expect(store.deleted, [41]);
      expect(store.valueOf(42)['name'], 'someone else');
      expect(store.valueOf(42)['bip353Address'], 'other@dana.example');
    });

    test('an adoption the unique key refuses costs the label, not the merge',
        () async {
      // The address of the doomed row belongs to a third contact, so the
      // survivor can not take it; the pair still has to collapse.
      store.insertAll([
        _contact(41, 'alice too', 'taken@dana.example', codeUpper),
        _contact(42, null, null, codeSeed),
        _contact(43, 'carol', 'taken@dana.example', 'sp1anothercoded0'),
      ]);

      await buildState().refreshContacts();

      expect(store.deleted, [41],
          reason: 'the duplicate is still gone — the label is the only loss');
      expect(store.valueOf(42)['bip353Address'], isNull,
          reason: 'the refused address did not land');
      expect(store.valueOf(43)['bip353Address'], 'taken@dana.example',
          reason: 'and the third contact kept what was its own');
    });

    test('an I/O failure is not read as a collision', () async {
      // A fault of the write reaches the pass as an Exception that is NOT a
      // DuplicateContactException -- in production that is the DatabaseException
      // of the driver, which the repository rethrows unharmed.
      store.onWrite = const _IoFailure('disk I/O error while writing contacts');
      store.insertAll([
        _contact(41, 'alice', null, codeUpper),
        _contact(42, 'alice too', null, codeSeed),
      ]);

      final state = buildState();
      await state.refreshContacts();
      expect(folded, contains(codeUpper));
      expect(store.rowOf(41)!['paymentCode'], codeUpper,
          reason: 'the row keeps its dirty spelling, as it must on a failure');
      expect(store.deleted, isEmpty,
          reason: 'a failure of the write must not reach the merge — under a '
              'bare Exception the pass would have called it a collision and '
              'deleted a row that never collided with anything');
      expect(state.getOtherContacts().map((c) => c.id), containsAll([41, 42]),
          reason: 'both rows are still listed, for neither was reconciled');

      folded.clear();
      store.onWrite = null;
      await state.refreshContacts();

      expect(folded, contains(codeUpper),
          reason: 'the latch stayed down, so the pass was retried and nothing '
              'was left in the old spelling unnoticed');
      expect(store.deleted, [41],
          reason: 'and once the write stood, the real collision was merged');
      expect(store.rowOf(41), isNull);
      expect(store.rowOf(42)!['name'], 'alice too');
    });
  });

  group('the lookups that read a stored key back', () {
    test('a contact answers to every spelling of its address', () async {
      store.insert(_contact(41, 'alice', null, codeSeed));
      final state = buildState();
      await state.initialize('sp1yourownencoded0', null);

      for (final probe in [codeSeed, codeUpper, codeMixed]) {
        expect(state.getContactByPaymentCode(probe)?.id, 41,
            reason: 'the list in memory holds the folded form while the chain '
                'records whatever the counterparty sent, and a byte-exact '
                'compare of the two renders the contact anonymous next to its '
                'own transactions');
      }
    });

    test('your own address is recognized in every spelling', () async {
      store.insert(_contact(41, 'alice', null, codeSeed));
      final state = buildState();
      await state.initialize(codeSeed, null);

      expect(state.getContactByPaymentCode(codeUpper)?.id, -1,
          reason: 'the self-check folds both of its sides');
    });
  });
}

Contact _contact(int id, String? name, String? address, String paymentCode) =>
    Contact(
      id: id,
      name: name,
      bip353Address: address == null ? null : Bip353Address.fromString(address),
      paymentCode: paymentCode,
    );

Map<String, Object?> _row(int id, int contactId, String type, String value) =>
    {
      'id': id,
      'contact_id': contactId,
      'field_type': type,
      'field_value': value,
    };

/// The shape a fault of the driver takes on its way out of the repository:
/// the DatabaseException of sqflite implements Exception and is rethrown
/// unharmed by the two arms that guard the writes, so the pass sees an
/// Exception that is not a DuplicateContactException.
class _IoFailure implements Exception {
  final String message;
  const _IoFailure(this.message);

  @override
  String toString() => message;
}

/// The contacts table of a v0.8.x install, in memory: the key columns
/// compare BYTE, exactly as migration 000 declared them and as they stay
/// until migration 003 rebuilds the table.
class _Store extends ContactsRepository {
  _Store() : super.forTesting();

  final Map<int, Map<String, Object?>> rows = {};
  final List<Map<String, Object?>> fields = [];
  final List<int> deleted = [];
  final List<int> writes = [];
  Object? onWrite;

  void insert(Contact contact) => rows[contact.id!] = _toRow(contact);
  void insertAll(Iterable<Contact> contacts) {
    for (final contact in contacts) {
      insert(contact);
    }
  }

  Map<String, Object?> valueOf(int id) => rows[id]!;
  Map<String, Object?>? rowOf(int id) => rows[id];

  List<String> ownersOf(int contactId) => fields
      .where((f) => f['contact_id'] == contactId)
      .map((f) => f['field_value']! as String)
      .toList();

  static Map<String, Object?> _toRow(Contact c) => {
        'id': c.id,
        'name': c.name,
        'bip353Address': c.bip353Address?.toString(),
        'paymentCode': c.paymentCode,
      };

  @override
  Future<List<Contact>> getAllContacts({required bool loadCustomFields}) async {
    final all = rows.values.map((r) => Contact.fromMap(r)).toList();
    if (!loadCustomFields) return all;
    return all
        .map((c) => Contact(
              id: c.id,
              name: c.name,
              bip353Address: c.bip353Address,
              paymentCode: c.paymentCode,
              customFields: fieldsOf(c.id!),
            ))
        .toList();
  }

  @override
  Future<Contact?> getContactByPaymentCode(String paymentCode,
      {bool loadCustomFields = false}) async {
    for (final r in rows.values) {
      if (r['paymentCode'] == paymentCode) return Contact.fromMap(r);
    }
    return null;
  }

  @override
  Future<Contact?> getContact(int id, {bool loadCustomFields = false}) async {
    final row = rows[id];
    if (row == null) return null;
    final contact = Contact.fromMap(row);
    if (!loadCustomFields) return contact;
    return Contact(
      id: contact.id,
      name: contact.name,
      bip353Address: contact.bip353Address,
      paymentCode: contact.paymentCode,
      customFields: fieldsOf(id),
    );
  }

  List<ContactField> fieldsOf(int contactId) => fields
      .where((f) => f['contact_id'] == contactId)
      .map((f) => ContactField(
            id: f['id'] as int,
            contactId: f['contact_id'] as int,
            fieldType: f['field_type']! as String,
            fieldValue: f['field_value']! as String,
          ))
      .toList();

  @override
  Future<int> updateContact(Contact contact) async {
    writes.add(contact.id!);
    if (onWrite != null) throw onWrite!;
    final clashOnKey = rows.values.any((r) =>
        r['id'] != contact.id &&
        (r['paymentCode'] == contact.paymentCode ||
            (contact.bip353Address != null &&
                r['bip353Address'] == contact.bip353Address.toString())));
    if (clashOnKey) {
      throw const DuplicateContactException(
          'Another contact already exists with this dana address or silent payment address');
    }
    rows[contact.id!] = _toRow(contact);
    return 1;
  }

  @override
  Future<int> deleteContact(int id) async {
    deleted.add(id);
    rows.remove(id);
    return 1;
  }

  @override
  Future<List<ContactField>> getContactFields(int contactId) async =>
      fieldsOf(contactId);

  @override
  Future<int> updateContactField(ContactField field) async {
    for (var i = 0; i < fields.length; i++) {
      if (fields[i]['id'] == field.id) {
        fields[i] = {
          'id': field.id,
          'contact_id': field.contactId,
          'field_type': field.fieldType,
          'field_value': field.fieldValue,
        };
        return 1;
      }
    }
    return 0;
  }
}
