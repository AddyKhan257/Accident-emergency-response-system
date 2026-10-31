import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await Api.get('/api/contacts');
      if (!mounted) return;
      setState(() => _items = d is List ? d : []);
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final rel = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add emergency contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              TextField(
                controller: rel,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Relation (Father, Wife...)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
      _snack('Name and phone are required');
      return;
    }
    try {
      await Api.post('/api/contacts', {
        'name': name.text.trim(),
        'phone': phone.text.trim(),
        'relation': rel.text.trim(),
      });
      await _load();
    } catch (e) {
      _snack(_msg(e));
    }
  }

  Future<void> _remove(Map c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('${c['name']} will no longer be notified.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('/api/contacts/${c['id']}');
      await _load();
    } catch (e) {
      _snack(_msg(e));
    }
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.darkRed)),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('No contacts yet.\nTap + to add a family member.',
            textAlign: TextAlign.center),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final c = _items[i] as Map;
          final n = '${c['name'] ?? ''}';
          final rel = '${c['relation'] ?? ''}';
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                child: Text(n.isEmpty ? '?' : n[0].toUpperCase()),
              ),
              title: Text(n),
              subtitle:
                  Text(rel.isEmpty ? '${c['phone']}' : '$rel  |  ${c['phone']}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.call),
                    onPressed: () => Api.dial(c['phone']?.toString()),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(c),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: _body(),
    );
  }
}
