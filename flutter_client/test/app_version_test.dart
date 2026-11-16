import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(NativeBridge.channel, null));
  test('version uses Android package metadata, never a source constant', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
      expect(call.method, 'appVersion');
      return '0.1.38';
    });
    expect(await NativeBridge.appVersion(), '内测版 0.1.38');
  });
  test('missing platform version is explicitly unknown', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
      throw PlatformException(code: 'version_unavailable');
    });
    expect(await NativeBridge.appVersion(), '版本未知');
  });
}
