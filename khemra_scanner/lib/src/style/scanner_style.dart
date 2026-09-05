import 'package:flutter/material.dart';

/// Visual configuration for the scanner camera and result screens.
class KhemraScannerStyle {
  final Color backgroundColor;
  final Color foregroundColor;
  final Color accentColor;
  final Color statusGoodColor;
  final Color statusBadColor;
  final String title;
  final String resultTitle;
  final String readyLabel;
  final String goodImageLabel;
  final String blurryImageLabel;
  final String retryLabel;
  final String useImageLabel;
  final Widget? overlay;
  final Widget? captureButton;

  const KhemraScannerStyle({
    this.backgroundColor = Colors.black,
    this.foregroundColor = Colors.white,
    this.accentColor = Colors.white,
    this.statusGoodColor = Colors.green,
    this.statusBadColor = Colors.red,
    this.title = 'ID Card Capture',
    this.resultTitle = 'Scan result',
    this.readyLabel = 'READY',
    this.goodImageLabel = 'GOOD IMAGE',
    this.blurryImageLabel = 'IMAGE IS BLURRY',
    this.retryLabel = 'Retry',
    this.useImageLabel = 'Use image',
    this.overlay,
    this.captureButton,
  });
}