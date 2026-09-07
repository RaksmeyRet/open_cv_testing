import 'package:flutter/foundation.dart';

abstract final class DevLog {
  static void log(String tag, {Object? message}) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  static void errorLog(String tag, {Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      debugPrint('[ERROR] $tag | $error');
      if (stackTrace != null) debugPrint(stackTrace.toString());
    }
  }
}
