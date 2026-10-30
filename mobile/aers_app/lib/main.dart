import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/splash.dart';

void main() {
  runApp(const AersApp());
}

class AersApp extends StatelessWidget {
  const AersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AERS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.red),
      ),
      home: const SplashScreen(),
    );
  }
}
