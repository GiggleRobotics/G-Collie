import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/api.dart';
import 'workspace_test.dart' show FakeApi;

class HomeApi extends FakeApi {
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/local') {
      return {
        'projects': [],
        'warnings': [],
        'sessions': [
          for (final agent in ['Codex', 'Hermes', 'Claude Code'])
            for (var i = 1; i <= 5; i++)
              {
                'id': '$agent:$i',
                'agent': agent,
                'title': '$agent recent $i',
                'updatedAt': i,
                'project': 'demo',
              },
        ],
      };
    }
    return super.call(path, body);
  }
}

void main() {
  testWidgets('seeded conversation renders on the first frame without a spinner', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    for (final agent in ['Codex', 'Hermes', 'Claude Code']) {
      await tester.pumpWidget(MaterialApp(home: Workspace(
        key: ValueKey(agent), api: HomeApi(), role: 'control',
        initialSession: 'demo', initialData: {
          'online': true, 'sessions': [], 'projects': [],
          'detail': {'id': 'demo', 'agent': agent, 'managed': true,
            'status': 'idle', 'events': [{'id':'first', 'role':'assistant', 'text':'首帧会话内容'}]},
        },
      )));
      expect(find.text('首帧会话内容', findRichText: true), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('assistant:Hermes')), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'home assistant cards filter four latest sessions without creating a chat',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = HomeApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'control'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assistant:Hermes')));
      await tester.pumpAndSettle();
      for (var i = 2; i <= 5; i++) {
        expect(find.text('Hermes recent $i').hitTestable(), findsOneWidget);
      }
      expect(find.text('Hermes recent 1'), findsNothing);
      expect(find.textContaining('Codex recent'), findsNothing);
      expect(api.created, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
