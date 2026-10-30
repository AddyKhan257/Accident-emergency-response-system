import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'severity.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const accidentTypes = [
    'Collision',
    'Hit and run',
    'Skid / fall',
    'Rollover',
    'Other'
  ];
  static const vehicleTypes = ['Bike', 'Car', 'Bus', 'Truck', 'Other'];

  String _accidentType = 'Collision';
  String _vehicleType = 'Car';
  int _people = 1;
  double _speed = 40;
  double _impact = 3;
  final _vehicleNo = TextEditingController();
  final _desc = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final acc = await Api.reportAccident(
        accidentType: _accidentType,
        vehicleNo: _vehicleNo.text.trim(),
        peopleCount: _people,
        description: _desc.text.trim(),
      );
      final pred = await Api.predict(
        vehicleType: _vehicleType,
        peopleCount: _people,
        speed: _speed,
        impactG: _impact,
        accidentId: acc['accident_id'],
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => SeverityScreen(accident: acc, prediction: pred),
      ));
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      );

  Widget _chips(List<String> items, String selected, void Function(String) on) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final i in items)
          ChoiceChip(
            label: Text(i),
            selected: selected == i,
            onSelected: (_) => setState(() => on(i)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Accident'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Accident type'),
            _chips(accidentTypes, _accidentType, (v) => _accidentType = v),
            _label('Vehicle type'),
            _chips(vehicleTypes, _vehicleType, (v) => _vehicleType = v),
            _label('Vehicle number (optional)'),
            TextField(
              controller: _vehicleNo,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  hintText: 'MH12AB1234', border: OutlineInputBorder()),
            ),
            _label('People involved'),
            Row(
              children: [
                IconButton.outlined(
                    onPressed:
                        _people > 1 ? () => setState(() => _people--) : null,
                    icon: const Icon(Icons.remove)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('$_people',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                IconButton.outlined(
                    onPressed:
                        _people < 50 ? () => setState(() => _people++) : null,
                    icon: const Icon(Icons.add)),
              ],
            ),
            _label('Estimated speed: ${_speed.round()} km/h'),
            Slider(
              value: _speed,
              min: 0,
              max: 160,
              divisions: 32,
              label: '${_speed.round()} km/h',
              onChanged: (v) => setState(() => _speed = v),
            ),
            _label('Impact strength: ${_impact.toStringAsFixed(1)} g'),
            Slider(
              value: _impact,
              min: 0,
              max: 15,
              divisions: 30,
              label: '${_impact.toStringAsFixed(1)} g',
              onChanged: (v) => setState(() => _impact = v),
            ),
            const Text(
                'Low = minor bump, high = hard crash. (Later this comes from the phone sensor.)',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            _label('Description (optional)'),
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'What happened?', border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.darkRed)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Submit & Predict Severity',
                        style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
