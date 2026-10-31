import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class HospitalsScreen extends StatelessWidget {
  const HospitalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hospitals & Police'),
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Hospitals'), Tab(text: 'Police')],
          ),
        ),
        body: const TabBarView(
          children: [
            _PlaceList(path: '/api/hospitals', icon: Icons.local_hospital),
            _PlaceList(path: '/api/police', icon: Icons.local_police),
          ],
        ),
      ),
    );
  }
}

class _PlaceList extends StatefulWidget {
  final String path;
  final IconData icon;
  const _PlaceList({required this.path, required this.icon});
  @override
  State<_PlaceList> createState() => _PlaceListState();
}

class _PlaceListState extends State<_PlaceList> {
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
      final loc = await Api.getLocation();
      final d = await Api.get('${widget.path}?lat=${loc.lat}&lng=${loc.lng}');
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

  @override
  Widget build(BuildContext context) {
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
    if (_items.isEmpty) return const Center(child: Text('Nothing found.'));
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
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                child: Icon(widget.icon),
              ),
              title: Text('${p['name']}'),
              subtitle: Text(
                  '${d == null ? '' : '${d.toStringAsFixed(1)} km  |  '}${p['phone'] ?? ''}'),
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
}
