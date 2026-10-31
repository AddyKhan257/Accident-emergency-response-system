import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF0D1B3E);
  static const red = Color(0xFFE53935);
  static const darkRed = Color(0xFFB71C1C);
}

/// Colour for a severity text: Severe red, Moderate orange, Minor green.
Color severityColor(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'severe':
      return AppColors.red;
    case 'moderate':
      return Colors.orange;
    case 'minor':
      return Colors.green;
    default:
      return Colors.grey;
  }
}
