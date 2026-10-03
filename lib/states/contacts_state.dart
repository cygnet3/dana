import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/data/models/contact_field.dart';
import 'package:danawallet/exceptions.dart';
import 'package:danawallet/extensions/bip321_uri.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/extensions/payment_code.dart';
import 'package:danawallet/generated/rust/api/validate.dart';
import 'package:danawallet/repositories/contacts_repository.dart';
import 'package:danawallet/services/bip353_resolver.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

/// Case-insensitive equality of two silent payment addresses.
///
/// A bech32 encoding is case-insensitive by construction, so a comparison
/// that reads the bytes as they were stored tells a caller that two different
/// spellings of one and the same destination are two different contacts --
/// whenever the row predates migration 003, or the probe is a raw value the
/// chain recorded or the user scanned. Every such probe folds both sides.
bool _samePaymentCode(String a, String b) => a.toLowerCase() == b.toLowerCase();

class ContactsState extends ChangeNotifier {
  Contact? _youContact;
  final List<Contact> _contacts = List.empty(growable: true);
  final ContactsRepository _repository;

  /// The folding of a payment code, as a seam. The production one is the Rust
  /// sanitizePaymentCode() behind the bridge; it is injectable so that the
  /// canonicalization pass below can be driven without the native library --
  /// which is why the merge it performs has never been covered by a test.
  final String Function(String code) _sanitize;

  ContactsState({
    ContactsRepository? repository,
    String Function(String code)? sanitize,
  })  : _repository = repository ?? ContactsRepository.instance,
        _sanitize = sanitize ?? ((code) => sanitizePaymentCode(address: code));

  // TODO: remove once users have migrated past the uppercase SP address bug.
  // checkUpperCases() runs once per session as the backstop of migration 003:
  // the rebuild of that migration now folds every stored spelling itself, so
  // all that can still arrive here is a row the migration never reached -- a
  // rolled-back open, or a write of an install that predates it.
  bool _isCheckedForUpperCase = false;

  Future<void> initialize(
      String paymentCode, Bip353Address? danaAddress) async {
    // Initialize the 'you' contact
    _youContact = Contact(
      id: -1,
      name: 'you',
      paymentCode: paymentCode,
      bip353Address: danaAddress,
    );

    await refreshContacts();
  }

  /// The identifiers the merge of this pass has already reconciled into the
  /// list, freshly read back from the table. The ordinary path must not add a
  /// stale copy of one of them over it: the loop still holds the contact as it
  /// was before the merge moved it, and the two orders a pair can arrive in
  /// would then decide whether the survivor keeps the identity it adopted.
  final Set<int> _mergedThisPass = {};

  /// Keeps the in-memory list telling one entry per contact identifier, in
  /// whatever order the pass below reaches them. Holding a contact twice
  /// until some later refreshContacts() -- a pass the latch above hides --
  /// would render the list a different one from the table.
  void _putContact(Contact contact) {
    _contacts
      ..removeWhere((element) => element.id == contact.id)
      ..add(contact);
  }

  Future<void> checkUpperCases(List<Contact> allContacts) async {
    _mergedThisPass.clear();
    var collisionFree = true;
    for (final contact in allContacts) {
      final code = contact.paymentCode;
      // The candidate is anything that is not the canonical spelling, which
      // is what the fold prints -- for a bech32 encoding, all lower. This
      // probe read first "the two leading characters are capitals" and then
      // "the whole string is capitals"; each of those was a proper subset of
      // the truth, so a valid address in any other mixture -- an uppercase
      // one that carries a single lowercase letter beyond position 1, as a
      // scanned QR code may well present it -- escaped here entirely and
      // coexisted with its twin forever.
      if (code.length >= 2 && code != code.toLowerCase()) {
        String? canonical;
        try {
          Logger().w(
              'Canonicalizing legacy payment code for contact id=${contact.id}');
          canonical = _sanitize(code);
          await _repository.updateContact(Contact(
            id: contact.id,
            name: contact.name,
            bip353Address: contact.bip353Address,
            paymentCode: canonical,
            customFields: contact.customFields,
          ));
          _putContact(Contact(
            id: contact.id,
            name: contact.name,
            bip353Address: contact.bip353Address,
            paymentCode: canonical,
            customFields: contact.customFields,
          ));
          continue;
        } on DuplicateContactException catch (e) {
          // The canonical spelling is already taken by the contact that owns
          // it: the repository reports that as a UNIQUE constraint violation.
          // Merge the pair instead of logging the clash and keeping both rows.
          if (await _mergeIntoTwin(contact, canonical)) {
            continue;
          }
          collisionFree = false;
          Logger().e(
              'Failed to canonicalize payment code for contact id=${contact.id}: $e');
        } on Exception catch (e) {
          // Every other failure -- a fold that rejects, an I/O error of the
          // open -- is not a collision and must not reach the merge on the
          // strength of a canonical string that may still be null. The latch
          // stays down, so the next refresh retries the pass.
          collisionFree = false;
          Logger().e(
              'Failed to canonicalize payment code for contact id=${contact.id}: $e');
        }
      }
      if (!_mergedThisPass.contains(contact.id)) {
        _putContact(contact);
      }
    }

    // Latch only after a pass that left no collision behind. It is an
    // in-memory field, so a failed pass is retried on the next refresh and
    // no duplicate pair can become permanent unnoticed — persisting the latch
    // is not needed for that, per-session retry is correct-by-retry.
    _isCheckedForUpperCase = collisionFree;
  }

  /// Reconciles a contact whose canonical payment code is already owned by a
  /// second contact: the survivor adopts whatever the doomed row held, the
  /// custom fields are re-attached to it, and the duplicate is deleted, so
  /// that one payment destination maps to one contact.
  ///
  /// Returns true when the pair was merged. It is reached only through a
  /// [DuplicateContactException], the one refusal that means a second row
  /// owns the key. It is NOT the backstop of the oldest-wins choice of
  /// migration 003: a same-row update to the canonical spelling SUCCEEDS
  /// under `paymentCode UNIQUE COLLATE NOCASE`, so what lands here is only
  /// ever a pair that the migration never reached -- a rolled-back open, or
  /// a row of an install that predates it.
  Future<bool> _mergeIntoTwin(Contact contact, String? canonical) async {
    if (canonical == null) return false;
    try {
      final twin = await _repository.getContactByPaymentCode(canonical);
      if (twin?.id == null || twin!.id == contact.id) return false;

      for (final field in await _repository.getContactFields(contact.id!)) {
        await _repository.updateContactField(ContactField(
          id: field.id,
          contactId: twin.id!,
          fieldType: field.fieldType,
          fieldValue: field.fieldValue,
        ));
      }
      await _repository.deleteContact(contact.id!);
      Logger().i(
          'Merged duplicate contact id=${contact.id} into canonical owner id=${twin.id}');

      // The row that stays keeps what it has and adopts only what it lacks,
      // from the row that is gone: the very same never-lose rule that the
      // rebuild of migration 003 applies to this pair. The name the user
      // typed and the Dana address they resolved may live on the doomed side
      // alone, and without this they would leave no trace at all. It runs
      // AFTER the delete above, for while the duplicate still stands it holds
      // a case-variant of the selfsame key and the NOCASE UNIQUE of the table
      // would refuse to write the survivor at all.
      var mergedName = twin.name;
      var mergedAddress = twin.bip353Address;
      final adoptedName = mergedName ?? contact.name;
      final adoptedAddress = mergedAddress ?? contact.bip353Address;

      Future<void> adopt(String? name, Bip353Address? address) async {
        try {
          await _repository.updateContact(Contact(
            id: twin.id,
            name: name,
            bip353Address: address,
            paymentCode: twin.paymentCode,
          ));
          mergedName = name;
          mergedAddress = address;
        } on Exception catch (e) {
          // The value adopted may belong to a third contact, which the UNIQUE
          // key of the table refuses. Each column is tried on its own, the
          // way the rebuild of the migration folds each of them on its own,
          // so that a refused address can not cost the name as well. Losing
          // either is the cheaper outcome: the pair still has to collapse, or
          // else the duplicate keeps its second row and the latch settles on
          // nothing.
          Logger().w('Could not adopt the identity of duplicate contact '
              'id=${contact.id} into id=${twin.id}: $e');
        }
      }

      if (adoptedName != mergedName || adoptedAddress != mergedAddress) {
        // The fold of the pair at once; should the table refuse it, each of
        // the columns is tried on its own, so that a taken address can not
        // cost the name as well.
        final lastName = mergedName;
        final lastAddress = mergedAddress;
        await adopt(adoptedName, adoptedAddress);
        if (mergedName == lastName && mergedAddress == lastAddress) {
          await adopt(adoptedName, lastAddress);
          await adopt(lastName, adoptedAddress);
        }
      }

      // Read the survivor back so the in-memory list tells the same story as
      // the database, custom fields and all.
      final survivor =
          await _repository.getContact(twin.id!, loadCustomFields: true) ??
              Contact(
                id: twin.id,
                name: mergedName,
                bip353Address: mergedAddress,
                paymentCode: twin.paymentCode,
              );
      _mergedThisPass.add(twin.id!);
      _putContact(survivor);
      return true;
    } catch (e) {
      Logger().e('Could not reconcile duplicate contact id=${contact.id}: $e');
      return false;
    }
  }

  Future<void> refreshContacts() async {
    // make sure we save no old state
    _contacts.clear();

    // then populate the rest of the contacts
    final allContacts =
        await _repository.getAllContacts(loadCustomFields: true);

    if (_isCheckedForUpperCase) {
      _contacts.addAll(allContacts);
    } else {
      await checkUpperCases(allContacts);
    }

    notifyListeners();
  }

  Future<void> setYouContactDanaAddress(Bip353Address? danaAddress) async {
    if (_youContact!.bip353Address != null) {
      throw Exception("you-contact bip353Address already set");
    }

    // overwrite the you-contact
    _youContact = Contact(
      id: _youContact!.id,
      name: _youContact!.name,
      paymentCode: _youContact!.paymentCode,
      bip353Address: danaAddress,
    );

    notifyListeners();
  }

  /// Adds a new contact by dana address
  /// Resolves the dana address to SP address via DNS before saving
  ///
  /// Throws [ArgumentError] if dana address format is invalid
  /// Throws [Exception] if dana address cannot be resolved or contact already exists
  Future<void> addContact({
    required String paymentCode,
    required Network network,
    Bip353Address? danaAddress,
    String? name,
  }) async {
    paymentCode = sanitizePaymentCode(address: paymentCode);

    if (_samePaymentCode(paymentCode, _youContact!.paymentCode)) {
      throw Exception("Adding yourself is not allowed");
    }
    // First check for duplicates
    final existing = await _repository.getContactByPaymentCode(paymentCode);
    if (existing != null) {
      throw Exception('Contact with sp address $paymentCode already exists');
    }

    // Resolve the SP address via DNS
    // Verify that the address is correct
    if (danaAddress != null) {
      final bip321Uri = await Bip353Resolver.resolveParsed(danaAddress);
      final resolvedPaymentCode =
          bip321Uri.reusablePaymentCodeForNetwork(network);
      if (resolvedPaymentCode == null) {
        throw Exception("$danaAddress doesn't contain a reusable payment code");
      } else if (sanitizePaymentCode(address: resolvedPaymentCode) !=
          paymentCode) {
        throw Bip353PaymentCodeMismatchException(
            address: danaAddress,
            expected: paymentCode,
            resolved: resolvedPaymentCode);
      }
    }

    // Store and update cached contact list
    final contact = Contact(
      bip353Address: danaAddress,
      paymentCode: paymentCode,
      name: name,
    );

    final id = await _repository.insertContact(contact);
    contact.id = id;

    _putContact(contact);

    Logger().i('Contact added successfully: $danaAddress -> $paymentCode');

    await refreshContacts();
  }

  Set<Bip353Address> getKnownBip353Addresses() {
    Set<Bip353Address> result = {};
    // add your own dana address
    if (_youContact?.bip353Address != null) {
      result.add(_youContact!.bip353Address!);
    }

    // add contacts dana address
    for (var contact in _contacts) {
      if (contact.bip353Address != null) {
        result.add(contact.bip353Address!);
      }
    }
    return result;
  }

  Set<String> getKnownPaymentCodes() {
    Set<String> result = {};
    // add your own payment code
    result.add(_youContact!.paymentCode);

    // add contacts payment codes
    for (var contact in _contacts) {
      result.add(contact.paymentCode);
    }
    return result;
  }

  Contact getYouContact() {
    return _youContact!;
  }

  List<Contact> getOtherContacts() {
    return _contacts;
  }

  int getOtherContactsCount() {
    return _contacts.length;
  }

  List<Contact> filterContacts(String query) {
    return _contacts.where((contact) {
      final displayName = contact.displayName?.toLowerCase();
      if (displayName != null) {
        return displayName.contains(query);
      } else {
        return false;
      }
    }).toList();
  }

  /// Creates the appropriate display widget for a given silent payment address, using data from the contact list
  /// Priority: contact name > contact dana address > SP address
  /// note: this may not be the best place to put this function, may be refactored out later
  Widget getDisplayNameWidget(BuildContext context, String paymentCode) {
    final Contact? contact = _contacts.firstWhereOrNull(
        (contact) => _samePaymentCode(contact.paymentCode, paymentCode));

    if (contact != null) {
      if (contact.name != null) {
        return Text(
          contact.name!,
          style: BitcoinTextStyle.body4(Bitcoin.black),
        );
      } else if (contact.bip353Address != null) {
        return contact.bip353Address!.asRichText(15.0);
      } else {
        return Text(
            paymentCode.chunked(
                context, BitcoinTextStyle.body4(Bitcoin.black), 0.53),
            style: BitcoinTextStyle.body4(Bitcoin.black));
      }
    } else {
      return Text(
        paymentCode.chunked(
            context, BitcoinTextStyle.body4(Bitcoin.black), 0.53),
        style: BitcoinTextStyle.body4(Bitcoin.black),
      );
    }
  }

  /// Updates an existing contact
  ///
  /// Throws [ArgumentError] if contact id is null
  /// Throws [Exception] if contact doesn't exist or update fails
  Future<void> updateContact(Contact contact) async {
    if (contact.id == null) {
      throw ArgumentError('Cannot update contact without id');
    }

    // Verify contact exists
    final existing = await _repository.getContact(contact.id!);
    if (existing == null) {
      throw Exception('Contact with id ${contact.id} not found');
    }

    final rowsUpdated = await _repository.updateContact(contact);
    if (rowsUpdated == 0) {
      throw Exception('Failed to update contact');
    }

    Logger().i('Contact updated successfully: ${contact.bip353Address}');

    await refreshContacts();
  }

  /// Deletes a contact by id
  Future<void> deleteContact(int id) async {
    final rowsDeleted = await _repository.deleteContact(id);
    final deleted = rowsDeleted > 0;

    if (deleted) {
      Logger().i('Contact deleted successfully: id=$id');
    } else {
      Logger().w('Contact not found for deletion: id=$id');
    }

    await refreshContacts();
  }

  // Contact Fields Management

  /// Adds a new custom field to a contact
  ///
  /// Throws [ArgumentError] if field type or value is empty
  /// Throws [Exception] if contact doesn't exist
  Future<ContactField> addContactField({
    required int contactId,
    required String fieldType,
    required String fieldValue,
  }) async {
    // Validate inputs
    if (fieldType.trim().isEmpty) {
      throw ArgumentError('Field type cannot be empty');
    }

    if (fieldValue.trim().isEmpty) {
      throw ArgumentError('Field value cannot be empty');
    }

    // Verify contact exists
    final contact = await _repository.getContact(contactId);
    if (contact == null) {
      throw Exception('Contact with id $contactId not found');
    }

    final field = ContactField(
      contactId: contactId,
      fieldType: fieldType.trim(),
      fieldValue: fieldValue.trim(),
    );

    final id = await _repository.insertContactField(field);
    field.id = id;

    Logger().i('Contact field added: $fieldType for contact $contactId');

    await refreshContacts();
    return field;
  }

  /// Updates an existing contact field
  ///
  /// Throws [ArgumentError] if field id is null or values are empty
  /// Throws [Exception] if field doesn't exist
  Future<void> updateContactField(ContactField field) async {
    if (field.id == null) {
      throw ArgumentError('Cannot update contact field without id');
    }

    if (field.fieldType.trim().isEmpty) {
      throw ArgumentError('Field type cannot be empty');
    }

    if (field.fieldValue.trim().isEmpty) {
      throw ArgumentError('Field value cannot be empty');
    }

    // Verify field exists
    final existing = await _repository.getContactField(field.id!);
    if (existing == null) {
      throw Exception('Contact field with id ${field.id} not found');
    }

    final rowsUpdated = await _repository.updateContactField(field);
    if (rowsUpdated == 0) {
      throw Exception('Failed to update contact field');
    }

    Logger().i('Contact field updated: ${field.fieldType} (id=${field.id})');

    await refreshContacts();
  }

  /// Deletes a contact field by id
  ///
  /// Returns true if field was deleted, false if not found
  Future<bool> deleteContactField(int id) async {
    final rowsDeleted = await _repository.deleteContactField(id);
    final deleted = rowsDeleted > 0;

    if (deleted) {
      Logger().i('Contact field deleted: id=$id');
    } else {
      Logger().w('Contact field not found for deletion: id=$id');
    }

    await refreshContacts();
    return deleted;
  }

  Contact? getContact(int id) {
    if (id == _youContact!.id) {
      return _youContact;
    } else {
      return _contacts.firstWhereOrNull((contact) => contact.id == id);
    }
  }

  Contact? getContactByPaymentCode(String paymentCode) {
    if (_samePaymentCode(paymentCode, _youContact!.paymentCode)) {
      return _youContact;
    } else {
      return _contacts.firstWhereOrNull(
          (contact) => _samePaymentCode(contact.paymentCode, paymentCode));
    }
  }

  /// Gets all custom fields for a contact
  Future<List<ContactField>> getContactFields(int contactId) async {
    return await _repository.getContactFields(contactId);
  }

  Future<void> reset() async {
    await _repository.deleteAllContacts();

    // extra precaution, shouldn't be needed
    _youContact = null;
    _contacts.clear();
  }
}
