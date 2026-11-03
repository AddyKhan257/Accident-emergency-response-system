import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../theme.dart';
import 'sos.dart';

/// Voice SOS: say "Help" / "Bachao" / "Madad" / "Vachva" and a 5 second
/// countdown starts; then the normal SOS is sent. English, Hindi, Marathi.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});
  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  static const langs = {
    'en_IN': 'English',
    'hi_IN': 'हिन्दी (Hindi)',
    'mr_IN': 'मराठी (Marathi)',
  };

  static const triggers = [
    // English
    'help', 'emergency', 'accident', 'sos', 'save me', 'ambulance',
    // Hindi (Latin + Devanagari)
    'bachao', 'bachaao', 'madad', 'दुर्घटना', 'बचाओ', 'मदद', 'एक्सीडेंट',
    'इमरजेंसी', 'हेल्प',
    // Marathi
    'vachva', 'madat', 'वाचवा', 'मदत', 'अपघात', 'आणीबाणी',
  ];

  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  bool _listening = false;
  String _lang = 'en_IN';
  String _text = '';
  String? _error;
  Set<String> _available = {};
  int? _count;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stt.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final ok = await _stt
          .initialize(
            onError: (e) {
              if (mounted) {
                setState(() {
                  _listening = false;
                  _error = '${e.errorMsg}';
                });
              }
            },
            onStatus: (s) {
              if (mounted && (s == 'done' || s == 'notListening')) {
                setState(() => _listening = false);
              }
            },
          )
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (!mounted) return;
      setState(() {
        _ready = ok;
        if (!ok) {
          _error =
              'Speech recognition could not start (${_stt.lastError?.errorMsg ?? 'no reason given'}). Check microphone permission and that the Google app is enabled.';
        }
      });
      if (ok) _loadLocales();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Language list is optional (only used for a warning), so it must never
  /// block the mic button.
  Future<void> _loadLocales() async {
    try {
      final ls = await _stt.locales().timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() => _available =
          ls.map((l) => l.localeId.replaceAll('-', '_')).toSet());
    } catch (_) {}
  }

  /// Picks the phone's locale for the chosen language: exact match first,
  /// otherwise any locale with the same language code (en_US for en_IN).
  String? _resolve(String lang) {
    if (_available.isEmpty || _available.contains(lang)) return lang;
    final p = lang.split('_').first;
    for (final l in _available) {
      if (l.split('_').first == p) return l;
    }
    return null;
  }

  Future<void> _toggle() async {
    if (!_ready || _count != null) return;
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() {
      _text = '';
      _error = null;
      _listening = true;
    });
    await _stt.listen(
      localeId: _resolve(_lang) ?? _lang,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 6),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _text = r.recognizedWords);
        _check(r.recognizedWords);
      },
    );
  }

  void _check(String words) {
    if (_count != null) return;
    final t = words.toLowerCase();
    if (triggers.any((w) => t.contains(w))) _startCountdown();
  }

  void _startCountdown() {
    _stt.stop();
    setState(() {
      _listening = false;
      _count = 5;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_count! <= 1) {
        t.cancel();
        _sendNow();
      } else {
        setState(() => _count = _count! - 1);
      }
    });
  }

  void _cancelCountdown() {
    _timer?.cancel();
    setState(() => _count = null);
  }

  void _sendNow() {
    _timer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SosScreen(autoSend: true)));
  }

  @override
  Widget build(BuildContext context) {
    final missing =
        _ready && _available.isNotEmpty && _resolve(_lang) == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice SOS'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final e in langs.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _lang == e.key,
                    onSelected: _listening || _count != null
                        ? null
                        : (_) => setState(() => _lang = e.key),
                  ),
              ],
            ),
            if (missing)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'This language is not installed on the phone. Add it in Google app > Settings > Voice > Languages.',
                    style: TextStyle(color: AppColors.darkRed, fontSize: 12)),
              ),
            const SizedBox(height: 24),
            const Text(
                'Tap the mic and say "Help", "Bachao", "Madad" or "Vachva"',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _toggle,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening ? AppColors.red : AppColors.navy,
                  boxShadow: _listening
                      ? [
                          BoxShadow(
                              color: AppColors.red.withOpacity(0.4),
                              blurRadius: 28,
                              spreadRadius: 8)
                        ]
                      : null,
                ),
                child: Icon(_listening ? Icons.stop : Icons.mic,
                    size: 60, color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            Text(_listening
                ? 'Listening...'
                : (_ready
                    ? 'Tap to speak'
                    : (_error != null ? 'Not available' : 'Starting...'))),
            const SizedBox(height: 20),
            Card(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 70),
                padding: const EdgeInsets.all(16),
                child: Text(_text.isEmpty ? '...' : _text,
                    style: const TextStyle(fontSize: 18)),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.darkRed)),
              ),
            const Spacer(),
            if (_count != null) ...[
              Text('Sending SOS in $_count',
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.red)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                    onPressed: _cancelCountdown,
                    child: const Text('CANCEL')),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                  onPressed: _sendNow,
                  child: const Text('Send alert now',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
