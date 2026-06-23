import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_full_screen_scanner_ios/flutter_full_screen_scanner_ios.dart';
import 'package:flutter_full_screen_scanner_ios/flutter_full_screen_scanner_ios_platform_interface.dart';
import 'package:flutter_full_screen_scanner_ios/flutter_full_screen_scanner_ios_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterFullScreenScannerIosPlatform
    with MockPlatformInterfaceMixin
    implements FlutterFullScreenScannerIosPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterFullScreenScannerIosPlatform initialPlatform =
      FlutterFullScreenScannerIosPlatform.instance;

  test('$MethodChannelFlutterFullScreenScannerIos is the default instance', () {
    expect(
      initialPlatform,
      isInstanceOf<MethodChannelFlutterFullScreenScannerIos>(),
    );
  });

  test('getPlatformVersion', () async {
    FlutterFullScreenScannerIos flutterFullScreenScannerIosPlugin =
        FlutterFullScreenScannerIos();
    MockFlutterFullScreenScannerIosPlatform fakePlatform =
        MockFlutterFullScreenScannerIosPlatform();
    FlutterFullScreenScannerIosPlatform.instance = fakePlatform;

    expect(await flutterFullScreenScannerIosPlugin.getPlatformVersion(), '42');
  });
}
