import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:native_opencv_kit/native_opencv.dart';
import 'package:native_opencv_kit_example/scan_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  Map<String, String>? _scanResult;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    String platformVersion;
    try {
      platformVersion = NativeOpencv.getOpenCVVersion();
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff243b7a)),
        scaffoldBackgroundColor: const Color(0xfff7f8fc),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'KhmerScan',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: Colors.transparent,
        ),
        // Builder gives us a context that sits BELOW MaterialApp,
        // so Navigator.of(context) inside it can find the Navigator.
        body: Builder(
          builder: (context) {
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(
                        color: const Color(0xff243b7a),
                        borderRadius: BorderRadius.circular(34),
                      ),
                      child: const Icon(
                        Icons.badge_outlined,
                        color: Colors.white,
                        size: 64,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'KhmerScan',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff182650),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Scan your ID card and review the details\nquickly and securely.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Color(0xff667085)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'OpenCV $_platformVersion',
                      style: const TextStyle(color: Color(0xff98a2b3)),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                        backgroundColor: const Color(0xff243b7a),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('Scan ID card'),
                      onPressed: () async {
                        final result = await Navigator.of(
                          context,
                        ).push<Map<String, String>>(
                          MaterialPageRoute(builder: (_) => const ScanScreen()),
                        );
                        if (!context.mounted || result == null) return;
                        setState(() => _scanResult = result);
                      },
                    ),
                    if (_scanResult != null) ...[
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ID card information',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ..._scanResult!.entries.map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 110,
                                        child: Text(
                                          entry.key,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Expanded(child: Text(entry.value)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
