import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api.dart';
import '../theme.dart';

class SeverityScreen extends StatefulWidget {
  final Map<String, dynamic> accident;
  final Map<String, dynamic> prediction;
  const SeverityScreen(
      {super.key, required this.accident, required this.prediction});

  @override
  State<SeverityScreen> createState() => _SeverityScreenState();
}

class _SeverityScreenState extends State<SeverityScreen> {
  List<dynamic>? _contacts;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final r = await http.get(
        Uri.parse('${Api.baseUrl}/api/contacts'),
        headers: {'Authorization': 'Bearer ${Api.token}'},
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        setState(() => _contacts = d is List ? d : []);
      } else {
        setState(() => _contacts = []);
      }
    } catch (_) {
      if (mounted) setState(() => _contacts = []);
    }
  }

  String _contactsText() {
    final c = _contacts;
    if (c == null) return 'Loading...';
    if (c.isEmpty) return 'No contacts added yet';
    return c.map((x) {
      if (x is Map) {
        final rel = x['relation'];
        return rel == null ? '${x['name']}' : '${x['name']} ($rel)';
      }
      return x.toString();
    }).join(', ');
  }

  Color _color(String s) {
    switch (s.toLowerCase()) {
      case 'severe':
        return AppColors.red;
      case 'moderate':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accident = widget.accident;
    final prediction = widget.prediction;
    final severity = (prediction['severity'] ?? 'Unknown').toString();
    final conf = double.tryParse(prediction['confidence'].toString());
    final c = _color(severity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Severity Prediction'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: c.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c, width: 2),
              ),
              child: Column(
                children: [
                  Icon(Icons.health_and_safety, size: 56, color: c),
                  const SizedBox(height: 8),
                  Text(severity.toUpperCase(),
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: c)),
                  const SizedBox(height: 4),
                  Text(
                      conf == null
                          ? 'Predicted by ML model'
                          : 'Confidence ${(conf * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(children: [
                ListTile(
                    leading: const Icon(Icons.local_hospital),
                    title: const Text('Nearest hospital'),
                    subtitle: Text(Api.place(accident['hospital']))),
                ListTile(
                    leading: const Icon(Icons.local_police),
                    title: const Text('Nearest police'),
                    subtitle: Text(Api.place(accident['police']))),
                ListTile(
                    leading: const Icon(Icons.family_restroom),
                    title: const Text('Family contacts'),
                    subtitle: Text(_contactsText())),
                ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Status'),
                    subtitle: Text(
                        '${accident['status'] ?? 'pending'}  |  ID ${accident['accident_id'] ?? '-'}')),
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
        ),
      ),
    );
  }
}
