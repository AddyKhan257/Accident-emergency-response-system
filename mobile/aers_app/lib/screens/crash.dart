import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../theme.dart';
import 'severity.dart';

/// Watches the accelerometer while the app is open. A sudden spike
/// (>= thresholdG) calls [onCrash]; the Home screen then shows the
/// "Are you OK?" countdown.
class CrashDetector {
  CrashDetector._();
  static final CrashDetector instance = CrashDetector._();

  /// 1 g = normal gravity. Hard shake / drop / impact gives several g.
  static const double thresholdG = 3.5;
  static const String _prefKey = 'crash_detection';

  StreamSubscription<AccelerometerEvent>? _sub;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  void Function(double g)? onCrash;

  bool get running => _sub != null;

  static Future<bool> savedEnabled() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_prefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveEnabled(bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefKey, v);
    } catch (_) {}
  }

  static double gForce(AccelerometerEvent e) =>
      sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 9.81;

  void start() {
    if (_sub != null) return;
    _sub = accelerometerEventStream().listen((e) {
      final g = gForce(e);
      if (g >= thresholdG) trigger(g);
    }, onError: (_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// [force] skips the 60 second cool-down (used by the demo button).
  void trigger(double g, {bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_last).inSeconds < 60) return;
    _last = now;
    onCrash?.call(g);
  }
}

// --------------------------------------------------------------- settings

class CrashScreen extends StatefulWidget {
  const CrashScreen({super.key});
  @override
  State<CrashScreen> createState() => _CrashScreenState();
}

class _CrashScreenState extends State<CrashScreen> {
  bool _on = false;
  double _g = 1.0;
  StreamSubscription<AccelerometerEvent>? _live;

  @override
  void initState() {
    super.initState();
    _on = CrashDetector.instance.running;
    _live = accelerometerEventStream().listen((e) {
      if (mounted) setState(() => _g = CrashDetector.gForce(e));
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _toggle(bool v) async {
    setState(() => _on = v);
    await CrashDetector.saveEnabled(v);
    if (v) {
      CrashDetector.instance.start();
    } else {
      CrashDetector.instance.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hot = _g >= CrashDetector.thresholdG;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crash Detection'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Automatic crash detection'),
              subtitle: const Text(
                  'If the phone feels a very strong impact, you get 10 seconds to cancel. After that an SOS is sent automatically.'),
              value: _on,
              onChanged: _toggle,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Live sensor reading',
                      style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 8),
                  Text('${_g.toStringAsFixed(2)} g',
                      style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: hot ? AppColors.red : AppColors.navy)),
                  const SizedBox(height: 4),
                  Text(
                      'Trigger level: ${CrashDetector.thresholdG} g (resting phone is about 1 g)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
              onPressed: () =>
                  CrashDetector.instance.trigger(6.2, force: true),
              icon: const Icon(Icons.science),
              label: const Text('Simulate a crash (demo)'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
              'Works while the app is open. Impact-to-severity uses the ML model with the measured impact; vehicle type "Other", 1 person and speed 50 km/h are assumed.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- countdown

class CrashCountdownScreen extends StatefulWidget {
  final double impactG;
  const CrashCountdownScreen({super.key, required this.impactG});
  @override
  State<CrashCountdownScreen> createState() => _CrashCountdownScreenState();
}

class _CrashCountdownScreenState extends State<CrashCountdownScreen> {
  int _left = 10;
  bool _sending = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
        setState(() => _left = 0);
        _sendAuto();
      } else {
        HapticFeedback.heavyImpact();
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendAuto() async {
    if (_sending) return;
    _timer?.cancel();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final loc = await Api.getLocation();
      final raw = await Api.post('/api/sos', {'lat': loc.lat, 'lng': loc.lng});
      final acc = Map<String, dynamic>.from(raw as Map);
      final id = acc['accident_id'];
      try {
        await Api.post(
            '/api/accidents/$id/mark-auto', {'impact_g': widget.impactG});
        acc['status'] = acc['status'] ?? 'pending';
      } catch (_) {}
      Map<String, dynamic> pred = {};
      try {
        pred = await Api.predict(
          vehicleType: 'Other',
          peopleCount: 1,
          speed: 50,
          impactG: widget.impactG.clamp(1.0, 12.0).toDouble(),
          accidentId: id,
        );
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => SeverityScreen(accident: acc, prediction: pred)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.darkRed,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.car_crash, size: 80, color: Colors.white),
                const SizedBox(height: 12),
                const Text('Crash detected',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Impact ${widget.impactG.toStringAsFixed(1)} g',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 28),
                if (_sending)
                  const Column(children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Sending SOS...',
                        style: TextStyle(color: Colors.white, fontSize: 18)),
                  ])
                else ...[
                  const Text('Are you OK?',
                      style: TextStyle(color: Colors.white, fontSize: 22)),
                  const SizedBox(height: 8),
                  Text('$_left',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 96,
                          fontWeight: FontWeight.bold)),
                  const Text('SOS will be sent automatically',
                      style: TextStyle(color: Colors.white70)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.yellow)),
                ],
                const SizedBox(height: 36),
                if (!_sending || _error != null) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.darkRed),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("I'M OK - CANCEL",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _sending ? null : _sendAuto,
                    child: const Text('Send help now',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
