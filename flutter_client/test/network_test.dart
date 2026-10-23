import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/native.dart';
import 'package:g_collie_flutter/api.dart';

void main() {
  test(
    'cold start waits for persisted Tailscale login instead of misreporting logout',
    () async {
      var calls = 0;
      await NativeBridge.waitForNetwork(
        () async => {'state': ++calls < 4 ? 'NeedsLogin' : 'Running'},
        pause: (_) async {},
      );
      expect(calls, 4);
    },
  );
  test(
    'real login requirement and offline state remain bounded and distinct',
    () async {
      var calls = 0;
      await expectLater(
        NativeBridge.waitForNetwork(() async {
          calls++;
          return {
            'state': 'NeedsLogin',
            'authURL': 'https://login.tailscale.com/a/test',
          };
        }, pause: (_) async {}),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 6);
      calls = 0;
      await expectLater(
        NativeBridge.waitForNetwork(() async {
          calls++;
          return {'state': 'Starting'};
        }, pause: (_) async {}),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 30);
    },
  );
  test('only Tailscale address ranges select private transport', () {
    expect(NativeBridge.embedded(Uri.parse('http://100.84.91.5:4310')), true);
    expect(
      NativeBridge.embedded(Uri.parse('https://computer.tailnet.ts.net')),
      true,
    );
    expect(NativeBridge.embedded(Uri.parse('http://100.1.2.3:4310')), false);
    expect(NativeBridge.embedded(Uri.parse('http://127.0.0.1:4310')), false);
  });
}
