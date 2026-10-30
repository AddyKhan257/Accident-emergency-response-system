import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});
  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await Api.sendSos();
      setState(() => _result = r);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _name(dynamic v) {
    if (v is Map) {
      final n = v['name'] ?? '-';
      final d = double.tryParse(v['distance_km'].toString());
      return d == null ? '$n' : '$n (${d.toStringAsFixed(1)} km)';
    }
    return v?.toString() ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Emergency'),
        backgroundColor: AppColors.darkRed,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _result == null ? _confirm() : _done(),
      ),
    );
  }

  Widget _confirm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.warning_amber_rounded,
            size: 90, color: AppColors.red),
        const SizedBox(height: 16),
        const Text('Send emergency alert?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
            'Your location will be shared with the nearest hospital, police station and your family contacts.',
            textAlign: TextAlign.center),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppColors.darkRed)),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: _busy ? null : _send,
            child: _busy
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('SEND ALERT', style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
      ],
    );
  }

  Widget _done() {
    final r = _result!;
    final family = r['family'];
    final famCount = family is List ? family.length : 0;
    return Column(
      children: [
        const Icon(Icons.check_circle, size: 80, color: Colors.green),
        const SizedBox(height: 12),
        const Text('Alert sent',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        Card(
          child: Column(children: [
            ListTile(
                leading: const Icon(Icons.local_hospital),
                title: const Text('Nearest hospital'),
                subtitle: Text(_name(r['hospital']))),
            ListTile(
                leading: const Icon(Icons.local_police),
                title: const Text('Nearest police'),
                subtitle: Text(_name(r['police']))),
            ListTile(
                leading: const Icon(Icons.family_restroom),
                title: const Text('Family notified'),
                subtitle: Text('$famCount contact(s)')),
            ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Status'),
                subtitle: Text(
                    '${r['status'] ?? 'pending'}  |  ID ${r['accident_id'] ?? '-'}')),
          ]),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Home')),
        ),
      ],
    );
  }
}