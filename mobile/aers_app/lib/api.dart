import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class Api {
  // adb reverse tcp:5000 tcp:5000 makes this work on a USB phone.
  // Emulator: http://10.0.2.2:5000 | Phone on Wi-Fi: http://LAPTOP-IP:5000
    static String baseUrl =
      const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:5000');

  // true = always send Pune coordinates (matches seeded hospitals)
  static bool demoLocation = true;

  static String? token;
  static String userName = '';

  static Future<void> loadToken() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
    userName = p.getString('name') ?? '';
  }

  static Future<void> _save(String t, String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('token', t);
    await p.setString('name', name);
    token = t;
    userName = name;
  }

  static Future<void> setName(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('name', name);
    userName = name;
  }

  static Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('name');
    token = null;
    userName = '';
  }

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static String _err(http.Response r) {
    try {
      final d = jsonDecode(r.body);
      return (d['error'] ?? d['msg'] ?? d['message'] ?? 'Error ${r.statusCode}')
          .toString();
    } catch (_) {
      return 'Error ${r.statusCode}';
    }
  }

  // ------------------------------------------------------------ small helpers

  /// "City Hospital (0.7 km)" from a {name, distance_km} map.
  static String place(dynamic v) {
    if (v is Map) {
      final n = v['name'] ?? '-';
      final d = double.tryParse(v['distance_km'].toString());
      return d == null ? '$n' : '$n (${d.toStringAsFixed(1)} km)';
    }
    return v?.toString() ?? '-';
  }

  /// "1 contact(s): Dad (Father)" from the family_notified list.
  static String familyText(dynamic family) {
    if (family is! List || family.isEmpty) return '0 contact(s)';
    final names = family.map((x) {
      if (x is Map) {
        final rel = x['relation'];
        return rel == null ? '${x['name']}' : '${x['name']} ($rel)';
      }
      return x.toString();
    }).join(', ');
    return '${family.length} contact(s): $names';
  }

  /// "2026-10-31 21:57:03" -> "2026-10-31 21:57"
  static String when(dynamic v) {
    final s = (v ?? '').toString();
    return s.length > 16 ? s.substring(0, 16) : s;
  }

  /// Opens the phone dialer.
  static Future<void> dial(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone.trim()));
  }

  // ------------------------------------------------------------ generic calls

  static Future<dynamic> _send(String method, String path,
      [Object? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final Future<http.Response> f;
    switch (method) {
      case 'POST':
        f = http.post(uri, headers: _headers(), body: jsonEncode(body ?? {}));
        break;
      case 'PUT':
        f = http.put(uri, headers: _headers(), body: jsonEncode(body ?? {}));
        break;
      case 'DELETE':
        f = http.delete(uri, headers: _headers());
        break;
      default:
        f = http.get(uri, headers: _headers());
    }
    final http.Response r;
    try {
      r = await f.timeout(const Duration(seconds: 20));
    } catch (_) {
      throw Exception(
          'Cannot reach server. Is Docker running and adb reverse done?');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(_err(r));
    }
    if (r.body.isEmpty) return null;
    return jsonDecode(r.body);
  }

  static Future<dynamic> get(String path) => _send('GET', path);
  static Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body);
  static Future<dynamic> put(String path, [Object? body]) =>
      _send('PUT', path, body);
  static Future<dynamic> delete(String path) => _send('DELETE', path);

  // ------------------------------------------------------------------- auth

  /// Returns null on success, or an error text.
  static Future<String?> login(String email, String password) async {
    try {
      final r = await http
          .post(Uri.parse('$baseUrl/api/login'),
              headers: _headers(),
              body: jsonEncode({'email': email, 'password': password}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return _err(r);
      final d = jsonDecode(r.body);
      final t = (d['token'] ?? d['access_token']).toString();
      final name = (d['user'] is Map ? d['user']['name'] : null) ?? '';
      await _save(t, name.toString());
      return null;
    } catch (e) {
      return 'Cannot reach server. Is Docker running and adb reverse done?';
    }
  }

  static Future<String?> register(
      String name, String email, String password, String phone) async {
    try {
      final r = await http
          .post(Uri.parse('$baseUrl/api/register'),
              headers: _headers(),
              body: jsonEncode({
                'name': name,
                'email': email,
                'password': password,
                'phone': phone,
              }))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200 && r.statusCode != 201) return _err(r);
      return await login(email, password);
    } catch (e) {
      return 'Cannot reach server. Is Docker running and adb reverse done?';
    }
  }

  // --------------------------------------------------------------- location

  static Future<({double lat, double lng})> getLocation() async {
    if (demoLocation) return (lat: 18.52, lng: 73.85);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }
    final p = await Geolocator.getCurrentPosition();
    return (lat: p.latitude, lng: p.longitude);
  }

  // ------------------------------------------------------------ SOS / report

  static Future<Map<String, dynamic>> sendSos() async {
    final loc = await getLocation();
    final d = await post('/api/sos', {'lat': loc.lat, 'lng': loc.lng});
    return Map<String, dynamic>.from(d as Map);
  }

  /// POST /api/accidents, then notifies the family contacts.
  /// The result always has a 'family_notified' list.
  static Future<Map<String, dynamic>> reportAccident({
    required String accidentType,
    required String vehicleNo,
    required int peopleCount,
    required String description,
  }) async {
    final loc = await getLocation();
    final d = await post('/api/accidents', {
      'lat': loc.lat,
      'lng': loc.lng,
      'accident_type': accidentType,
      'vehicle_no': vehicleNo,
      'people_count': peopleCount,
      'description': description,
    });
    final acc = Map<String, dynamic>.from(d as Map);
    try {
      final n = await post('/api/accidents/${acc['accident_id']}/notify-family');
      acc['family_notified'] = n is Map ? (n['family_notified'] ?? []) : [];
    } catch (_) {
      acc['family_notified'] = [];
    }
    return acc;
  }

  /// POST /api/predict : ML severity. accidentId saves the result in the DB.
  static Future<Map<String, dynamic>> predict({
    required String vehicleType,
    required int peopleCount,
    required double speed,
    required double impactG,
    dynamic accidentId,
  }) async {
    final d = await post('/api/predict', {
      'vehicle_type': vehicleType,
      'people_count': peopleCount,
      'speed': speed,
      'impact_g': impactG,
      'hour': DateTime.now().hour,
      if (accidentId != null) 'accident_id': accidentId,
    });
    return Map<String, dynamic>.from(d as Map);
  }
}
