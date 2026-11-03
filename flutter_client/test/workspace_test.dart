import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/main.dart';

class FakeApi extends CollieApi {
  final calls = <String>[];
  Json? sent;
  Json? pending;
  String status = 'idle';
  String agent = 'Codex';
  Json? created;
  Json? projectAdded;
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
    if (path.startsWith('/folders')) {
      final selected = path.contains('path=');
      return {
        'path': selected ? '/home/test/demo' : '/home/test',
        'parent': selected ? '/home/test' : null,
        'folders': selected
            ? []
            : [
                {'name': '工作目录', 'path': '/home/test/demo'},
              ],
      };
    }
    if (path == '/projects') {
      projectAdded = body;
      return {
        'name': body!['name'],
        'path': body['path'],
        'agents': [],
        'sessions': 0,
      };
    }
    if (path == '/sessions') {
      created = body;
      return {'id': 'codex:one'};
    }
    if (path == '/desktop/one') {
      sent = body;
      return {'ok': true};
    }
    return {
      'id': 'codex:one',
      'nativeId': 'one',
      'title': 'Example session',
      'agent': agent,
      'claudeLive': agent == 'Claude Code',
      'hermesLive': agent == 'Hermes',
      'desktopLive': true,
      'desktopControl': true,
      'status': pending == null ? status : 'waiting',
      if (status == 'running') 'turnId': 'active-turn',
      if (pending != null) 'pending': pending,
      'events': [
        {'role': 'assistant', 'text': 'Hello from computer'},
      ],
    };
  }
}

class LongHistoryApi extends FakeApi {
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    final value = await super.call(path, body);
    if (path == '/local/codex%3Aone') {
      value['events'] = List.generate(
        60,
        (i) => {
          'id': '$i',
          'role': 'assistant',
          'text': 'Message $i\nLong conversation history',
        },
      );
    }
    return value;
  }
}

void main() {
  testWidgets('jump to latest appears above history and returns to bottom', (
    tester,
  ) async {
    final api = LongHistoryApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example session'));
    await tester.pumpAndSettle();
    final list = find.byType(ListView).last;
    await tester.drag(list, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.byTooltip('跳到最新消息'), findsOneWidget);
    await tester.tap(find.byTooltip('跳到最新消息'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('跳到最新消息'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
    'running composer accepts text; empty draft stops, content sends',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeApi()..status = 'running';
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'control'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example session'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('停止当前轮'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '补充要求');
      await tester.pump();
      expect(find.byTooltip('停止当前轮'), findsNothing);
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(api.sent?['action'], 'send');
      expect(api.sent?['text'], '补充要求');
      expect(find.byTooltip('停止当前轮'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'new session opens blank composer and creates only on first send',
    (tester) async {
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
      await tester.tap(find.byTooltip('新建会话'));
      await tester.pumpAndSettle();
      expect(find.text('新会话设置'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('session-start')))
            .onPressed,
        isNull,
      );
      final codex = tester.getTopLeft(
        find.byKey(const ValueKey('session-agent:Codex')),
      );
      final hermes = tester.getTopLeft(
        find.byKey(const ValueKey('session-agent:Hermes')),
      );
      final claude = tester.getTopLeft(
        find.byKey(const ValueKey('session-agent:Claude Code')),
      );
      expect(codex.dy, hermes.dy);
      expect(codex.dy, claude.dy);
      expect(codex.dx, lessThan(hermes.dx));
      await tester.tap(find.byKey(const ValueKey('session-agent:Hermes')));
      await tester.pumpAndSettle();
      expect(find.text('新会话设置'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('session-start')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('session-project:')));
      await tester.pumpAndSettle();
      expect(find.text('新会话设置'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('session-start')));
      await tester.tap(find.byKey(const ValueKey('session-start')));
      await tester.pumpAndSettle();
      expect(find.text('名称'), findsNothing);
      expect(find.text('第一条消息'), findsNothing);
      expect(api.created, isNull);
      await tester.enterText(find.byType(TextField).last, '帮我写一份报告');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(api.created?['prompt'], '帮我写一份报告');
      expect(api.created?.containsKey('title'), false);
      expect(api.created?['draftId'], 'draft:${api.created?['requestId']}');
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'plus project card opens project creation; chosen folder is confirmed before chatting',
    (tester) async {
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
      await tester.tap(find.byTooltip('新建会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-agent:Hermes')));
      await tester.pumpAndSettle();
      expect(find.text('选择已有文件夹'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('session-new-project')),
      );
      await tester.tap(find.byKey(const ValueKey('session-new-project')));
      await tester.pumpAndSettle();
      expect(find.text('新建文件夹'), findsOneWidget);
      await tester.tap(find.text('选择已有文件夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('工作目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择此文件夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加项目'));
      await tester.pumpAndSettle();
      expect(api.projectAdded?['path'], '/home/test/demo');
      expect(find.text('新会话设置'), findsOneWidget);
      expect(api.created, isNull);
      await tester.tap(find.byKey(const ValueKey('session-start')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'hello');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(api.created?['cwd'], '/home/test/demo');
      expect(api.created?['agent'], 'Hermes');
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  for (final agent in ['Codex', 'Hermes', 'Claude Code']) {
    testWidgets('$agent shares enabled photo, video and file actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeApi()..agent = agent;
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'control'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example session'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
      for (final action in ['添加照片', '添加视频', '手机文件', '引用电脑目录']) {
        expect(
          tester.widget<ListTile>(find.widgetWithText(ListTile, action)).onTap,
          isNotNull,
        );
      }
      expect(
        find.text('添加网址'),
        agent == 'Hermes' ? findsOneWidget : findsNothing,
      );
      if (agent == 'Hermes') {
        await tester.tap(find.text('添加网址'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).last,
          'https://example.com/help',
        );
        await tester.tap(find.text('插入草稿'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .controller!
              .text,
          contains('https://example.com/help'),
        );
      }
      await tester.pumpWidget(const SizedBox());
      api.close();
    });
  }
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
