import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'login.dart';
import 'report.dart';
import 'sos.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _soon(BuildContext c, String what) {
    ScaffoldMessenger.of(c)
        .showSnackBar(SnackBar(content: Text('$what - coming soon')));
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <(IconData, String, VoidCallback)>[
      (
        Icons.car_crash,
        'Report Accident',
        () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ReportScreen()))
      ),
      (Icons.my_location, 'My Location', () => _soon(context, 'My Location')),
      (
        Icons.contacts,
        'Emergency Contacts',
        () => _soon(context, 'Emergency Contacts')
      ),
      (Icons.history, 'Recent Status', () => _soon(context, 'Recent Status')),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text(
            Api.userName.isEmpty ? 'AERS' : 'Welcome, ${Api.userName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Api.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 32),
          const Text('In an emergency, press SOS',
              style: TextStyle(fontSize: 16, color: Colors.black54)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SosScreen())),
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.red,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.red.withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 8)
                ],
              ),
              alignment: Alignment.center,
              child: const Text('SOS',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(16),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                for (final t in tiles)
                  Card(
                    child: InkWell(
                      onTap: t.$3,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(t.$1, size: 36, color: AppColors.navy),
                          const SizedBox(height: 8),
                          Text(t.$2, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
