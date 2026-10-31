import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show Marker;
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../theme.dart';
import 'osm_map.dart';

/// Shows an accident on the map with the (simulated) ambulance coming to it.
/// Polls the backend every 5 seconds until the ambulance arrives.
class TrackScreen extends StatefulWidget {
  final int accidentId;
  const TrackScreen({super.key, required this.accidentId});
  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  double _n(dynamic v) => double.parse('$v');

  Future<void> _poll() async {
    try {
      final d = await Api.get('/api/accidents/${widget.accidentId}/track');
      if (!mounted) return;
      final m = Map<String, dynamic>.from(d as Map);
      setState(() {
        _data = m;
        _error = null;
      });
      if (m['arrived'] == true) _timer?.cancel();
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    }
  }

  Future<void> _dispatch() async {
    setState(() => _busy = true);
    try {
      await Api.post('/api/accidents/${widget.accidentId}/dispatch');
      _startTimer();
      await _poll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_msg(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _content(Map<String, dynamic> d) {
    final acc = Map<String, dynamic>.from(d['accident'] as Map);
    final amb = d['ambulance'] == null
        ? null
        : Map<String, dynamic>.from(d['ambulance'] as Map);
    final hospital = d['hospital'] is Map ? d['hospital'] as Map : null;
    final spot = LatLng(_n(acc['lat']), _n(acc['lng']));
    final markers = <Marker>[pin(spot, Icons.location_on, AppColors.red)];
    if (amb != null) {
      markers.add(pin(LatLng(_n(amb['lat']), _n(amb['lng'])),
          Icons.airport_shuttle, Colors.blue.shade800));
    }
    final arrived = d['arrived'] == true;
    final sev = acc['severity']?.toString();

    return Column(
      children: [
        SizedBox(height: 300, child: OsmMap(center: spot, markers: markers)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (arrived)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Ambulance has arrived',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.health_and_safety,
                          color: severityColor(sev)),
                      title: Text('Severity: ${sev ?? 'Not rated'}'),
                      subtitle: Text(
                          'Status: ${acc['status']}  |  ID ${acc['id']}'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.local_hospital),
                      title: const Text('Hospital'),
                      subtitle: Text(hospital == null
                          ? '-'
                          : '${hospital['name']}'),
                      trailing: hospital == null
                          ? null
                          : IconButton(
                              icon:
                                  const Icon(Icons.call, color: Colors.green),
                              onPressed: () =>
                                  Api.dial(hospital['phone']?.toString()),
                            ),
                    ),
                    if (amb == null)
                      ListTile(
                        leading: const Icon(Icons.airport_shuttle),
                        title: const Text('Ambulance'),
                        subtitle: const Text('Not requested yet'),
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.red),
                          onPressed: _busy ? null : _dispatch,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Request'),
                        ),
                      )
                    else ...[
                      ListTile(
                        leading: const Icon(Icons.airport_shuttle),
                        title: Text('${amb['vehicle_no']}'),
                        subtitle: Text('Driver: ${amb['driver_name'] ?? '-'}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.call, color: Colors.green),
                          onPressed: () => Api.dial(amb['phone']?.toString()),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined),
                        title: Text(arrived
                            ? 'At the accident spot'
                            : 'Arriving in about ${d['eta_min']} min'),
                        subtitle: Text('${d['distance_km']} km away'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text('Ambulance movement is simulated for the demo.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ambulance Tracking'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: d == null
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
          : _content(d),
    );
  }
}
