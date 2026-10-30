import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class SeverityScreen extends StatelessWidget {
  final Map<String, dynamic> accident;
  final Map<String, dynamic> prediction;
  const SeverityScreen(
      {super.key, required this.accident, required this.prediction});

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
    final severity = (prediction['severity'] ?? 'Unknown').toString();
    final conf = double.tryParse(prediction['confidence'].toString());
    final family = accident['family'];
    final famCount = family is List ? family.length : 0;
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
                    title: const Text('Family notified'),
                    subtitle: Text('$famCount contact(s)')),
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
