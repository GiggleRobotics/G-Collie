import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/native.dart';
import 'package:g_collie_flutter/api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('unresponsive network bridge returns a recoverable timeout', (
    tester,
  ) async {
    const channel = MethodChannel('dev.giggle.gcollie/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => Completer<String>().future);
    final result = expectLater(
      NativeBridge.invoke<String>('networkStatus'),
      throwsA(isA<ApiException>()),
    );
    await tester.pump(const Duration(seconds: 21));
    await result;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
