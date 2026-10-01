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

class ContactsState extends ChangeNotifier {
  Contact? _youContact;
  final List<Contact> _contacts = List.empty(growable: true);
  final ContactsRepository _repository = ContactsRepository.instance;

  // TODO: remove once users have migrated past the uppercase SP address bug.
  // checkUpperCases() runs once per session to canonicalize any all-uppercase
  // payment codes that were stored before sanitizePaymentCode() was introduced.
  bool _isCheckedForUpperCase = false;

  ContactsState();

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

  Future<void> checkUpperCases(List<Contact> allContacts) async {
    var collisionFree = true;
    for (final contact in allContacts) {
      final code = contact.paymentCode;
      // Same population as migration 002 (`payment_code = upper(payment_code)`):
      // a whole-string all-uppercase check. The previous code[0]/code[1] probe
      // was only a "starts with two capitals" proxy, so a valid bech32 spelling
      // that carries a lowercase letter beyond position 1 escaped here entirely
      // and coexisted with its lowercase twin as two distinct contacts.
      if (code.length >= 2 && code == code.toUpperCase()) {
        String? canonical;
        try {
          Logger().w(
              'Canonicalizing legacy payment code for contact id=${contact.id}');
          canonical = sanitizePaymentCode(address: code);
          await _repository.updateContact(Contact(
            id: contact.id,
            name: contact.name,
            bip353Address: contact.bip353Address,
            paymentCode: canonical,
            customFields: contact.customFields,
          ));
          _contacts.add(Contact(
            id: contact.id,
            name: contact.name,
            bip353Address: contact.bip353Address,
            paymentCode: canonical,
            customFields: contact.customFields,
          ));
          continue;
        } on Exception catch (e) {
          // The canonical spelling is already taken by the contact that owns it:
          // the repository reports that as a UNIQUE constraint violation. Merge
          // the pair instead of logging the clash and keeping both rows.
          if (await _mergeIntoTwin(contact, canonical)) {
            continue;
          }
          collisionFree = false;
          Logger().e(
              'Failed to canonicalize payment code for contact id=${contact.id}: $e');
        }
      }
      _contacts.add(contact);
    }

    // Latch only after a pass that left no collision behind. It is an
    // in-memory field, so a failed pass is retried on the next refresh and
    // no duplicate pair can become permanent unnoticed — persisting the latch
    // is not needed for that, per-session retry is correct-by-retry.
    _isCheckedForUpperCase = collisionFree;
  }

  /// Reconciles a contact whose canonical payment code is already owned by a
  /// second contact: the custom fields are re-attached to the survivor and the
  /// duplicate row is deleted, so one payment destination maps to one contact.
  ///
  /// Returns true when the pair was merged. Under migration 003
  /// (`paymentCode UNIQUE COLLATE NOCASE`) the database itself refuses a
  /// case-variant pair, so this path only ever runs on data written before it —
  /// defence-in-depth rather than the primary guarantee.
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

      // Read the survivor back so the in-memory list tells the same story as
      // the database, custom fields and all.
      final survivor =
          await _repository.getContact(twin.id!, loadCustomFields: true);
      _contacts.add(survivor ?? twin);
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

    if (paymentCode == _youContact!.paymentCode) {
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

    _contacts.add(contact);

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
    final Contact? contact = _contacts
        .firstWhereOrNull((contact) => contact.paymentCode == paymentCode);

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
    if (paymentCode == _youContact!.paymentCode) {
      return _youContact;
    } else {
      return _contacts
          .firstWhereOrNull((contact) => contact.paymentCode == paymentCode);
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
