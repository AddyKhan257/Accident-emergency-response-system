import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class DonorsScreen extends StatefulWidget {
  const DonorsScreen({super.key});
  @override
  State<DonorsScreen> createState() => _DonorsScreenState();
}

class _DonorsScreenState extends State<DonorsScreen> {
  static const groups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  List<dynamic> _items = [];
  String _bg = ''; // '' = all
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loc = await Api.getLocation();
      final q = 'lat=${loc.lat}&lng=${loc.lng}'
          '${_bg.isEmpty ? '' : '&blood_group=${Uri.encodeQueryComponent(_bg)}'}';
      final d = await Api.get('/api/donors?$q');
      if (!mounted) return;
      setState(() => _items = d is List ? d : []);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _list() {
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
      return const Center(child: Text('No donors found for this group.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final p = _items[i] as Map;
          final d = double.tryParse('${p['distance_km']}');
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                child: Text('${p['blood_group'] ?? '?'}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              title: Text('${p['name']}'),
              subtitle: Text(
                  '${p['city'] ?? ''}${d == null ? '' : '  |  ${d.toStringAsFixed(1)} km'}'),
              trailing: IconButton(
                icon: const Icon(Icons.call, color: Colors.green),
                onPressed: () => Api.dial(p['phone']?.toString()),
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
        title: const Text('Blood Donors'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _bg.isEmpty,
                    onSelected: (_) {
                      setState(() => _bg = '');
                      _load();
                    },
                  ),
                  for (final g in groups)
                    ChoiceChip(
                      label: Text(g),
                      selected: _bg == g,
                      onSelected: (_) {
                        setState(() => _bg = g);
                        _load();
                      },
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: _list()),
        ],
      ),
    );
  }
}
