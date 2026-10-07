import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/emergency_contact.dart';
import '../services/storage_service.dart';

class ContactsScreen extends StatefulWidget {
  final StorageService storageService;

  const ContactsScreen({super.key, required this.storageService});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<EmergencyContact> _contacts = [];
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contacts = await widget.storageService.loadContacts();
    setState(() => _contacts = contacts);
  }

  Future<void> _save() async {
    await widget.storageService.saveContacts(_contacts);
  }

  void _addOrEditContact({EmergencyContact? existing}) {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final phoneController = TextEditingController(text: existing?.phoneNumber ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Add Emergency Contact' : 'Edit Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone number (e.g. +234...)'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty ||
                  phoneController.text.trim().isEmpty) {
                return;
              }
              setState(() {
                if (existing != null) {
                  existing.name = nameController.text.trim();
                  existing.phoneNumber = phoneController.text.trim();
                } else {
                  _contacts.add(EmergencyContact(
                    id: _uuid.v4(),
                    name: nameController.text.trim(),
                    phoneNumber: phoneController.text.trim(),
                    priority: _contacts.length + 1,
                  ));
                }
              });
              await _save();
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteContact(EmergencyContact contact) async {
    setState(() => _contacts.remove(contact));
    for (var i = 0; i < _contacts.length; i++) {
      _contacts[i].priority = i + 1;
    }
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contacts')),
      body: _contacts.isEmpty
          ? const Center(child: Text('No emergency contacts yet. Tap + to add one.'))
          : ReorderableListView.builder(
              itemCount: _contacts.length,
              onReorder: (oldIndex, newIndex) async {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _contacts.removeAt(oldIndex);
                  _contacts.insert(newIndex, item);
                  for (var i = 0; i < _contacts.length; i++) {
                    _contacts[i].priority = i + 1;
                  }
                });
                await _save();
              },
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                return ListTile(
                  key: ValueKey(contact.id),
                  leading: CircleAvatar(child: Text('${contact.priority}')),
                  title: Text(contact.name),
                  subtitle: Text(contact.phoneNumber),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _addOrEditContact(existing: contact),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteContact(contact),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditContact(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
