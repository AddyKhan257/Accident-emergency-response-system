import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'login.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const groups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _email = '';
  String _bg = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _load() async {
    try {
      final d = await Api.get('/api/profile');
      if (!mounted) return;
      final m = Map<String, dynamic>.from(d as Map);
      setState(() {
        _name.text = '${m['name'] ?? ''}';
        _phone.text = '${m['phone'] ?? ''}';
        _email = '${m['email'] ?? ''}';
        _bg = '${m['blood_group'] ?? ''}';
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.put('/api/me', {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'blood_group': _bg,
      });
      await Api.setName(_name.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_msg(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    await Api.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.darkRed)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Center(
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                        child: Icon(Icons.person, size: 44),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                        child: Text(_email,
                            style: const TextStyle(color: Colors.black54))),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Phone', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 18),
                    const Text('Blood group',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final g in groups)
                          ChoiceChip(
                            label: Text(g),
                            selected: _bg == g,
                            onSelected: (_) =>
                                setState(() => _bg = _bg == g ? '' : g),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.red),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                    ),
                  ],
                ),
    );
  }
}
