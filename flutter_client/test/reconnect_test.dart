import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/ui.dart';
import 'package:g_collie_flutter/api.dart';
import 'workspace_test.dart' show FakeApi;

class ReconnectApi extends FakeApi {
  Completer<void>? gate;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/local' && gate != null) await gate!.future;
    return super.call(path, body);
  }
}

void main() {
  testWidgets(
    'explicit reconnect reports progress and result while preserving conversation draft',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = ReconnectApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'control'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example session'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'keep my draft');
      await tester.pump();
      api.gate = Completer<void>();
      final reconnect = tester
          .widget<CollieShell>(find.byType(CollieShell))
          .onReconnect!();
      await tester.pump();
      expect(
        tester.widget<CollieShell>(find.byType(CollieShell)).reconnecting,
        isTrue,
      );
      expect(find.text('正在重新连接当前电脑…'), findsOneWidget);
      api.gate!.complete();
      await reconnect;
      await tester.pumpAndSettle();
      expect(find.text('已重新连接当前电脑'), findsOneWidget);
      expect(find.text('keep my draft'), findsOneWidget);
      expect(find.text('Hello from computer'), findsOneWidget);
      expect(
        tester.widget<CollieShell>(find.byType(CollieShell)).reconnecting,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
