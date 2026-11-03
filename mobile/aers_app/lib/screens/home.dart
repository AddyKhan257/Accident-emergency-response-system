import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'contacts.dart';
import 'crash.dart';
import 'donors.dart';
import 'history.dart';
import 'hospitals.dart';
import 'livemap.dart';
import 'login.dart';
import 'profile.dart';
import 'report.dart';
import 'sos.dart';
import 'voice.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _crashOpen = false;

  @override
  void initState() {
    super.initState();
    CrashDetector.instance.onCrash = _onCrash;
    CrashDetector.savedEnabled().then((on) {
      if (on) CrashDetector.instance.start();
    });
  }

  @override
  void dispose() {
    CrashDetector.instance.onCrash = null;
    CrashDetector.instance.stop();
    super.dispose();
  }

  Future<void> _onCrash(double g) async {
    if (_crashOpen || !mounted) return;
    _crashOpen = true;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CrashCountdownScreen(impactG: g)));
    _crashOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <(IconData, String, Widget)>[
      (Icons.car_crash, 'Report Accident', const ReportScreen()),
      (Icons.my_location, 'Live Location', const LiveMapScreen()),
      (Icons.contacts, 'Emergency Contacts', const ContactsScreen()),
      (Icons.history, 'Accident History', const HistoryScreen()),
      (Icons.local_hospital, 'Hospitals & Police', const HospitalsScreen()),
      (Icons.bloodtype, 'Blood Donors', const DonorsScreen()),
      (Icons.mic, 'Voice SOS', const VoiceScreen()),
      (Icons.sensors, 'Crash Detection', const CrashScreen()),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text(
            Api.userName.isEmpty ? 'AERS' : 'Welcome, ${Api.userName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
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
          const SizedBox(height: 24),
          const Text('In an emergency, press SOS',
              style: TextStyle(fontSize: 16, color: Colors.black54)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SosScreen())),
            child: Container(
              width: 170,
              height: 170,
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
                      fontSize: 46,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.35,
              padding: const EdgeInsets.all(16),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                for (final t in tiles)
                  Card(
                    child: InkWell(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => t.$3)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(t.$1, size: 32, color: AppColors.navy),
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
