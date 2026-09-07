import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_opencv_kit/native_opencv.dart';
import 'package:native_opencv_kit/native_opencv_platform_interface.dart';
import 'package:native_opencv_kit/native_opencv_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockNativeOpencvPlatform
    with MockPlatformInterfaceMixin
    implements NativeOpencvPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final NativeOpencvPlatform initialPlatform = NativeOpencvPlatform.instance;

  test('$MethodChannelNativeOpencv is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelNativeOpencv>());
  });

  test('getPlatformVersion', () async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    MockNativeOpencvPlatform fakePlatform = MockNativeOpencvPlatform();
    NativeOpencvPlatform.instance = fakePlatform;

    expect(NativeOpencv.getOpenCVVersion(), '42');
  });
}
