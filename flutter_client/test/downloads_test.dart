import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/downloads.dart';
import 'package:g_collie_flutter/native.dart';

void main() {
  testWidgets(
    'downloads show actual system states and filter completed files',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeBridge.channel,
        (call) async => call.method == 'downloads'
            ? [
                {'id': 1, 'name': 'done.png', 'status': 8},
                {'id': 2, 'name': 'failed.pdf', 'status': 16, 'reason': 1006},
              ]
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeBridge.channel,
          null,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: DownloadsPage()));
      await tester.pumpAndSettle();
      expect(find.text('done.png'), findsOneWidget);
      expect(find.text('failed.pdf'), findsOneWidget);
      await tester.tap(find.text('已完成'));
      await tester.pumpAndSettle();
      expect(find.text('failed.pdf'), findsNothing);
      expect(find.text('打开'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
