import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'track.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _items = [];
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
      final d = await Api.get('/api/my/accidents');
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

  String _title(Map a) {
    final src = '${a['source'] ?? ''}';
    final type = a['accident_type'];
    final base = src == 'sos'
        ? 'SOS alert'
        : (type == null || '$type'.isEmpty ? 'Accident' : '$type');
    return '$base  |  ${a['severity'] ?? 'Unrated'}';
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
      return const Center(child: Text('No accidents reported yet.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final a = _items[i] as Map;
          final sev = a['severity']?.toString();
          return Card(
            child: ListTile(
              isThreeLine: true,
              leading: CircleAvatar(
                backgroundColor: severityColor(sev),
                foregroundColor: Colors.white,
                child: const Icon(Icons.car_crash),
              ),
              title: Text(_title(a)),
              subtitle: Text(
                  '${Api.when(a['created_at'])}\n${a['status']}  |  ${a['hospital_name'] ?? '-'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final id = int.tryParse('${a['id']}');
                if (id == null) return;
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TrackScreen(accidentId: id)));
              },
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
        title: const Text('Accident History'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: _body(),
    );
  }
}
