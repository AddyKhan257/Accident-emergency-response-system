import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

class Api {
  // adb reverse tcp:5000 tcp:5000 makes this work on a USB phone.
  // Emulator: http://10.0.2.2:5000 | Phone on Wi-Fi: http://LAPTOP-IP:5000
  static String baseUrl = 'http://localhost:5000';

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

  static Future<Map<String, dynamic>> sendSos() async {
    final loc = await getLocation();
    final r = await http
        .post(Uri.parse('$baseUrl/api/sos'),
            headers: _headers(),
            body: jsonEncode({'lat': loc.lat, 'lng': loc.lng}))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw Exception(_err(r));
    }
    return Map<String, dynamic>.from(jsonDecode(r.body));
  }
}
