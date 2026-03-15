import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/models/contact.dart';
import 'package:danawallet/screens/contacts/add_contact_sheet.dart';
import 'package:danawallet/screens/contacts/contact_details.dart';
import 'package:danawallet/states/contacts_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterContacts);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterContacts);
    _searchController.dispose();
    super.dispose();
  }

  void _filterContacts() {
    // Trigger rebuild so `_buildSearchResults` re-reads `_searchController.text`.
    setState(() {});
  }

  void _onTapContact(BuildContext context, Contact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContactDetailsScreen(contactId: contact.id!),
      ),
    );
  }

  Widget _buildContactItem(Contact contact) {
    final displayName = contact.displayName;
    final initial = contact.displayNameInitial;
    final avatarColor = contact.avatarColor;

    return ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: avatarColor,
          child: Text(
            initial,
            style:
                BitcoinTextStyle.body3(Bitcoin.white).apply(fontWeightDelta: 2),
          ),
        ),
        title: Text(
          displayName,
          style:
              BitcoinTextStyle.body3(Bitcoin.black).apply(fontWeightDelta: 2),
        ),
        onTap: () => _onTapContact(context, contact));
  }

  void _openAddContactSheet() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddContactSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contactsState = Provider.of<ContactsState>(context);
    final hasContacts = contactsState.getOtherContactsCount() > 0;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Contacts',
          style: BitcoinTextStyle.title4(Bitcoin.black),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddContactSheet,
        backgroundColor: Bitcoin.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // 'You' contact at the top
            _buildContactItem(contactsState.getYouContact()),
            const SizedBox(height: 20),
            // Search bar
            TextField(
              controller: _searchController,
              enabled: hasContacts,
              style: BitcoinTextStyle.body4(Bitcoin.black),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Search contacts',
                hintText: 'Search by name or address',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 20),
            // List of contacts and remote addresses
            Expanded(
              child: !hasContacts
                  ? Center(
                      child: Text(
                        'No contacts yet',
                        style: BitcoinTextStyle.body3(Bitcoin.neutral6),
                      ),
                    )
                  : _buildSearchResults(contactsState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(ContactsState contactsState) {
    final query = _searchController.text.toLowerCase().trim();
    
    final displayContacts = query.length < 3 
        ? contactsState.getOtherContacts() 
        : contactsState.filterContacts(query);
    
    return ListView.separated(
      itemCount: displayContacts.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        return _buildContactItem(displayContacts[index]);
      },
    );
  }
}
