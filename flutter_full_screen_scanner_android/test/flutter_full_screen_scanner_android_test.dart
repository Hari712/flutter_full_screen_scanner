import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_full_screen_scanner_android/flutter_full_screen_scanner_android.dart';
import 'package:flutter_full_screen_scanner_android/flutter_full_screen_scanner_android_platform_interface.dart';
import 'package:flutter_full_screen_scanner_android/flutter_full_screen_scanner_android_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterFullScreenScannerAndroidPlatform
    with MockPlatformInterfaceMixin
    implements FlutterFullScreenScannerAndroidPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterFullScreenScannerAndroidPlatform initialPlatform = FlutterFullScreenScannerAndroidPlatform.instance;

  test('$MethodChannelFlutterFullScreenScannerAndroid is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterFullScreenScannerAndroid>());
  });

  test('getPlatformVersion', () async {
    FlutterFullScreenScannerAndroid flutterFullScreenScannerAndroidPlugin = FlutterFullScreenScannerAndroid();
    MockFlutterFullScreenScannerAndroidPlatform fakePlatform = MockFlutterFullScreenScannerAndroidPlatform();
    FlutterFullScreenScannerAndroidPlatform.instance = fakePlatform;

    expect(await flutterFullScreenScannerAndroidPlugin.getPlatformVersion(), '42');
  });
}
