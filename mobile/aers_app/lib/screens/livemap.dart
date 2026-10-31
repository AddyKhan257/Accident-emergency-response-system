import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show Marker;
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../theme.dart';
import 'osm_map.dart';

/// My location + nearby hospitals and police stations on an OpenStreetMap map.
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});
  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  LatLng? _me;
  final List<Marker> _markers = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loc = await Api.getLocation();
      final q = '?lat=${loc.lat}&lng=${loc.lng}';
      final hs = await Api.get('/api/hospitals$q');
      final ps = await Api.get('/api/police$q');
      final me = LatLng(loc.lat, loc.lng);
      final m = <Marker>[
        pin(me, Icons.person_pin_circle, AppColors.red),
      ];
      if (hs is List) {
        for (final h in hs) {
          m.add(pin(LatLng(double.parse('${h['lat']}'), double.parse('${h['lng']}')),
              Icons.local_hospital, Colors.green.shade700));
        }
      }
      if (ps is List) {
        for (final p in ps) {
          m.add(pin(LatLng(double.parse('${p['lat']}'), double.parse('${p['lng']}')),
              Icons.local_police, Colors.indigo));
        }
      }
      if (!mounted) return;
      setState(() {
        _me = me;
        _markers
          ..clear()
          ..addAll(m);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Widget _legend(IconData i, Color c, String t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(i, color: c, size: 20), const SizedBox(width: 4), Text(t)],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Location'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: _me == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.darkRed)),
                    ),
            )
          : Column(
              children: [
                Expanded(child: OsmMap(center: _me!, zoom: 13, markers: _markers)),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      _legend(Icons.person_pin_circle, AppColors.red, 'You'),
                      _legend(Icons.local_hospital, Colors.green.shade700,
                          'Hospital'),
                      _legend(Icons.local_police, Colors.indigo, 'Police'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
