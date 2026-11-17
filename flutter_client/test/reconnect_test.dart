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
  bool failDetail = false;
  bool activationTimeout = false;
  int? rejection;
  int detailReads = 0, writes = 0;
  @override
  Future<bool> reachable() async => true;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (body != null) writes++;
    if (activationTimeout && path.endsWith('/activate')) {
      throw TimeoutException('synthetic activation outcome unknown');
    }
    if (path == '/local/codex%3Aone') {
      detailReads++;
      if (rejection != null) {
        throw ApiException('synthetic rejected', rejection!);
      }
    }
    if (path == '/local/codex%3Aone' && failDetail) {
      failDetail = false;
      throw TimeoutException('synthetic detail interruption');
    }
    if (path == '/local' && gate != null) await gate!.future;
    final result = await super.call(path, body);
    if (path == '/local/codex%3Atwo' && result is Map) {
      result['id'] = 'codex:two';
    }
    if (activationTimeout && path == '/local/codex%3Aone' && result is Map) {
      result['desktopLive'] = false;
    }
    if (path.startsWith('/local/') &&
        result is Map &&
        result['events'] is List) {
      result['events'] = [
        {
          'id': 'stable-qa-1',
          'role': 'assistant',
          'text': 'Hello from computer',
        },
      ];
    }
    return result;
  }
}

void main() {
  testWidgets(
    'first detail interruption retries without requiring a second selection',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = ReconnectApi()..failDetail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'control'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example session'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Hello from computer'), findsOneWidget);
      expect(find.textContaining('会话请求暂未完成'), findsNothing);
      expect(api.detailReads, greaterThanOrEqualTo(2));
      expect(api.writes, 0);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Hello from computer'), findsOneWidget);
      expect(api.writes, 0);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('unknown activation outcome never replays activation POST', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = ReconnectApi()..activationTimeout = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example session'));
    await tester.pumpAndSettle();
    expect(api.writes, 1);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(api.writes, 1);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  for (final status in [403, 404]) {
    testWidgets('detail $status does not retry automatically', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = ReconnectApi()..rejection = status;
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'control'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example session'));
      await tester.pumpAndSettle();
      final before = api.detailReads;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(api.detailReads, before);
      expect(api.writes, 0);
      await tester.pumpWidget(const SizedBox());
      api.close();
    });
  }
  testWidgets('selecting another session clears failed open retry', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = ReconnectApi()..failDetail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example session'));
    await tester.pumpAndSettle();
    final before = api.detailReads;
    final dynamic state = tester.state(find.byType(Workspace));
    await state.open('codex:two');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(api.detailReads, before);
    expect(api.writes, 0);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
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
