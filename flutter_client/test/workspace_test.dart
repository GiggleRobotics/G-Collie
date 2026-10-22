import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/main.dart';

class FakeApi extends CollieApi {
  final calls = <String>[];
  Json? sent;
  Json? pending;
  FakeApi() : super(Uri.parse('http://localhost:4310'));
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    calls.add(path);
    if (path == '/local') {
      return {
        'sessions': [
          {
            'id': 'codex:one',
            'title': 'Example session',
            'agent': 'Codex',
            'project': 'G-Collie',
          },
        ],
        'projects': [],
        'warnings': [],
      };
    }
    if (path == '/desktop/one') {
      sent = body;
      return {'ok': true};
    }
    return {
      'id': 'codex:one',
      'nativeId': 'one',
      'title': 'Example session',
      'agent': 'Codex',
      'desktopLive': true,
      'desktopControl': true,
      'status': pending == null ? 'idle' : 'waiting',
      if (pending != null) 'pending': pending,
      'events': [
        {'role': 'assistant', 'text': 'Hello from computer'},
      ],
    };
  }
}

void main() {
  testWidgets('open history and send to original desktop session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example session'));
    await tester.pumpAndSettle();
    expect(find.text('Hello from computer'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Test message');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '发送'),
    );
    await tester.pumpAndSettle();
    expect(api.sent?['text'], 'Test message');
    expect(api.sent?['action'], 'send');
    expect(api.sent?['requestId'], matches(RegExp('^[a-f0-9]{32}\$')));
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('read-only device sees history but cannot send or create', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'view'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example session'));
    await tester.pumpAndSettle();
    final send = tester.widget<IconButton>(
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '发送'),
    );
    final create = tester.widget<IconButton>(
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '新建会话'),
    );
    expect(send.onPressed, isNull);
    expect(create.onPressed, isNull);
    expect(api.calls.where((p) => p.endsWith('/activate')), isEmpty);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('question draft keeps cursor and text during live refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi()
      ..pending = {
        'id': 'question-one',
        'kind': 'question',
        'params': {
          'questions': [
            {'id': 'choice', 'question': 'Choose a mode'},
          ],
        },
      };
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example session'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'draft answer');
    final controller = tester
        .widget<TextFormField>(find.byType(TextFormField))
        .controller!;
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(controller.text, 'draft answer');
    expect(controller.selection.baseOffset, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
