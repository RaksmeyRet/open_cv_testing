import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/khemra_scanner_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: KhemraScannerScreen(),
    ),
  );
}
