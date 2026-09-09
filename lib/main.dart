import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'screens/khemra_scanner_screen.dart';

void main() {
  runApp(
    const GetMaterialApp(
      debugShowCheckedModeBanner: false,
      home: KhemraScannerScreen(),
    ),
  );
}
