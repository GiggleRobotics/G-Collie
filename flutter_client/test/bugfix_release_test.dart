import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/ui.dart';
import 'package:g_collie_flutter/resources.dart';
import 'package:g_collie_flutter/session_video.dart';
import 'workspace_test.dart' show FakeApi;

class MessageMediaApi extends FakeApi {
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    final result = await super.call(path, body);
    if (path == '/local/codex%3Aone') {
      final photo =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7ZkAAAAASUVORK5CYII=';
      result['events'] = [
        {
          'id': 'old',
          'role': 'user',
          'text': '前一条多图',
          'media': [
            photo,
            photo.replaceFirst('image/png;', 'image/png;charset=utf-8;'),
          ],
        },
        {
          'id': 'single',
          'role': 'user',
          'text': '当前单图',
          'media': [photo],
        },
        {
          'id': 'mixed',
          'role': 'user',
          'text': '[录屏.mp4](/clip.mp4)',
          'media': [photo],
        },
      ];
    }
    return result;
  }
}

class RefreshApi extends FakeApi {
  Completer<dynamic>? response;
  bool serverError = false;
  bool transportError = false;
  bool healthReachable = true;
  @override
  Future<bool> reachable() async => healthReachable;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/local/codex%3Aone') {
      if (transportError) throw ApiException('会话请求超时');
      if (serverError) throw ApiException('会话接口暂时失败', 503);
      if (response != null) return response!.future;
    }
    return super.call(path, body);
  }
}

class ProjectApi extends FakeApi {
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/local') {
      return {
        'sessions': [],
        'warnings': [],
        'projects': [
          for (final name in ['alpha', 'beta'])
            {'name': name, 'path': '/$name'},
        ],
      };
    }
    if (path == '/usage') {
      return {
        'agents': {
          'Codex': {
            'projects': [
              {
                'path': '/alpha',
                'usage': {'total': 128000},
              },
            ],
          },
          'Hermes': {
            'projects': [
              {
                'path': '/beta',
                'usage': {'total': 0},
              },
            ],
          },
          'Claude Code': {
            'projects': [
              {
                'path': '/beta',
                'usage': {'total': 1800000},
              },
            ],
          },
        },
      };
    }
    return super.call(path, body);
  }
}

class SendApi extends FakeApi {
  final history = Completer<dynamic>();
  final operations = <Json>[];
  bool submitted = false;
  bool unknown = false;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/desktop/one') {
      operations.add(body!);
      if (unknown) throw ApiException('请求结果未知');
      submitted = true;
      return {'ok': true};
    }
    if (path == '/local/codex%3Aone' && submitted) return history.future;
    return super.call(path, body);
  }
}

class NewSessionApi extends FakeApi {
  final history = Completer<dynamic>();
  bool createdSession = false;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/sessions') {
      createdSession = true;
      return super.call(path, body);
    }
    if (createdSession && path == '/local/codex%3Aone') return history.future;
    return super.call(path, body);
  }
}

class SlowSendApi extends FakeApi {
  final ack = Completer<dynamic>();
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/desktop/one') return ack.future;
    return super.call(path, body);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('each message owns its gallery and single photos stay separate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = MessageMediaApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control', initialSession: 'codex:one'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final galleries = tester
        .widgetList<SessionGallery>(find.byType(SessionGallery))
        .toList();
    expect(galleries.length, 2);
    expect(galleries.first.sources.length, 2);
    expect(galleries.first.videos, isEmpty);
    expect(galleries.last.sources.length, 2);
    expect(galleries.last.sources.last, '/clip.mp4');
    expect(galleries.last.videos, contains('/clip.mp4'));
    expect(find.text('当前单图'), findsOneWidget);
    expect(find.byType(SessionImage), findsWidgets);
    expect(find.byType(SessionVideo), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
    'created session retains conversation while first history is loading',
    (tester) async {
      final api = NewSessionApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'control'),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<CollieShell>(find.byType(CollieShell)).onCreate();
      await tester.pumpAndSettle();
      var shell = tester.widget<CollieShell>(find.byType(CollieShell));
      shell.draft.text = '新会话首条消息';
      final sending = shell.onSend([]);
      await tester.pump();
      shell = tester.widget<CollieShell>(find.byType(CollieShell));
      expect(shell.loading, true);
      expect(shell.detail?['id'], 'codex:one');
      expect(shell.detail?['events'], isNotEmpty);
      expect(find.text('今天想继续哪项工作？'), findsNothing);
      api.history.complete({
        'id': 'codex:one',
        'agent': 'Codex',
        'title': '新会话',
        'desktopLive': true,
        'status': 'running',
        'events': [],
      });
      expect(await sending, true);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CollieShell>(find.byType(CollieShell)).detail?['id'],
        'codex:one',
      );
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('sent first message is not restored in the next new session', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'workspace-drafts:http://localhost:4310': '{"__new__":"旧版已发送内容"}',
    });
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control'),
      ),
    );
    await tester.pumpAndSettle();
    tester.widget<CollieShell>(find.byType(CollieShell)).onCreate();
    await tester.pumpAndSettle();
    var shell = tester.widget<CollieShell>(find.byType(CollieShell));
    expect(shell.draft.text, isEmpty);
    shell.draft.text = '第一条消息';
    await tester.pump(const Duration(milliseconds: 350));
    expect(await shell.onSend([]), true);
    await tester.pumpAndSettle();
    expect(api.created?['prompt'], '第一条消息');
    shell = tester.widget<CollieShell>(find.byType(CollieShell));
    expect(shell.draft.text, isEmpty);
    shell.onCreate();
    await tester.pumpAndSettle();
    expect(
      tester.widget<CollieShell>(find.byType(CollieShell)).draft.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('sent text is visible before a slow desktop acknowledges it', (
    tester,
  ) async {
    final api = SlowSendApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control', initialSession: 'codex:one'),
      ),
    );
    await tester.pumpAndSettle();
    final shell = tester.widget<CollieShell>(find.byType(CollieShell));
    shell.draft.text = '慢链路即时显示';
    final send = shell.onSend([]);
    await tester.pump();
    final current = tester.widget<CollieShell>(find.byType(CollieShell));
    expect(
      current.detail!['events']
          .where((e) => e['text'] == '慢链路即时显示')
          .single['sendStatus'],
      'sending',
    );
    api.ack.complete({'ok': true, 'turnId': 'verified-turn'});
    expect(await send, true);
    await tester.pump();
    expect(
      tester
          .widget<CollieShell>(find.byType(CollieShell))
          .detail!['events']
          .where((e) => e['text'] == '慢链路即时显示')
          .single['sendStatus'],
      'sent',
    );
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
    'acknowledged send clears draft before history completes and survives history failure',
    (tester) async {
      final api = SendApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(
            api: api,
            role: 'control',
            initialSession: 'codex:one',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shell = tester.widget<CollieShell>(find.byType(CollieShell));
      shell.draft.text = '发送已确认';
      expect(await shell.onSend(['photo']), true);
      await tester.pump();
      expect(shell.draft.text, isEmpty);
      expect(tester.widget<CollieShell>(find.byType(CollieShell)).busy, false);
      api.history.completeError(ApiException('历史读取超时'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CollieShell>(find.byType(CollieShell)).error,
        contains('消息已发送'),
      );
      expect(tester.widget<CollieShell>(find.byType(CollieShell)).online, true);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'unconfirmed send retains its request id when the user retries the same content',
    (tester) async {
      final api = SendApi()..unknown = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(
            api: api,
            role: 'control',
            initialSession: 'codex:one',
          ),
        ),
      );
      await tester.pumpAndSettle();
      var shell = tester.widget<CollieShell>(find.byType(CollieShell));
      shell.draft.text = '不要重复发送';
      expect(await shell.onSend([]), false);
      await tester.pump();
      shell = tester.widget<CollieShell>(find.byType(CollieShell));
      expect(await shell.onSend([]), false);
      expect(api.operations[0]['requestId'], api.operations[1]['requestId']);
      expect(shell.draft.text, '不要重复发送');
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'transport failure marks offline only when health probe fails and recovers',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = RefreshApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(
            api: api,
            role: 'control',
            initialSession: 'codex:one',
          ),
        ),
      );
      await tester.pumpAndSettle();
      api.transportError = true;
      await tester.tap(find.byTooltip('刷新会话'));
      await tester.pumpAndSettle();
      expect(tester.widget<CollieShell>(find.byType(CollieShell)).online, true);
      api.healthReachable = false;
      await tester.tap(find.byTooltip('刷新会话'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CollieShell>(find.byType(CollieShell)).online,
        false,
      );
      expect(find.text('Hello from computer'), findsOneWidget);
      api.transportError = false;
      api.healthReachable = true;
      await tester.widget<CollieShell>(find.byType(CollieShell)).onRefresh();
      await tester.pumpAndSettle();
      expect(tester.widget<CollieShell>(find.byType(CollieShell)).online, true);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('project usage slots align across numeric and missing values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ProjectApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打开会话列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目管理'));
    await tester.pumpAndSettle();
    for (final agent in ['Codex', 'Hermes', 'Claude Code']) {
      final slots = find.byTooltip('$agent · 累计 Token');
      expect(slots, findsNWidgets(2));
      expect(
        tester.getTopLeft(slots.at(0)).dx,
        tester.getTopLeft(slots.at(1)).dx,
      );
      final firstText = find
          .descendant(of: slots.at(0), matching: find.byType(Text))
          .first;
      final secondText = find
          .descendant(of: slots.at(1), matching: find.byType(Text))
          .first;
      expect(tester.getTopLeft(firstText).dx, tester.getTopLeft(secondText).dx);
    }
    expect(find.text('128K'), findsOneWidget);
    expect(find.text('1.8M'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('—'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
    'landscape home shows assistants and recent sessions without scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(890, 400);
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
      expect(tester.takeException(), isNull);
      expect(find.text('Example session').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Example session'));
      await tester.pumpAndSettle();
      expect(find.text('Hello from computer'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );

  testWidgets(
    'refresh retains conversation, draft, toolbar and lifecycle connection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = RefreshApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(
            api: api,
            role: 'control',
            initialSession: 'codex:one',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.byTooltip('新建会话'));
      await tester.enterText(find.byType(TextField).last, '保留未发送草稿');
      api.response = Completer<dynamic>();
      await tester.tap(find.byTooltip('刷新会话'));
      await tester.pump();
      expect(find.text('今天想继续哪项工作？'), findsNothing);
      expect(find.text('保留未发送草稿'), findsOneWidget);
      expect(tester.getTopLeft(find.byTooltip('新建会话')), before);
      api.response!.complete(await FakeApi().call('/local/codex%3Aone'));
      await tester.pumpAndSettle();
      expect(find.text('保留未发送草稿'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(tester.widget<CollieShell>(find.byType(CollieShell)).online, true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      api.response = null;
      api.serverError = true;
      await tester.tap(find.byTooltip('刷新会话'));
      await tester.pumpAndSettle();
      expect(tester.widget<CollieShell>(find.byType(CollieShell)).online, true);
      expect(find.text('保留未发送草稿'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
