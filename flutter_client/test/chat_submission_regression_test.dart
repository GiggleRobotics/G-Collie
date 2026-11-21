import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/ui.dart';
import 'workspace_test.dart' show FakeApi;
import 'offline_workspace_test.dart' show OfflineApi;

class SubmissionApi extends FakeApi {
  final acknowledgement = Completer<dynamic>();
  bool confirmed = false;
  int submissions = 0;
  String? submittedRequest;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/desktop/one') {
      submissions++;
      submittedRequest = body!['requestId'];
      return acknowledgement.future;
    }
    final data = await super.call(path, body);
    if (path == '/local/codex%3Aone' && confirmed) {
      data['sendReceipts'] = [
        {'requestId': submittedRequest, 'turnId': 'actual-turn'},
      ];
    }
    return data;
  }
}

class ConversationSendApi extends FakeApi {
  final submissions = <Json>[];
  final first = Completer<dynamic>();

  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path.startsWith('/desktop/')) {
      submissions.add({'path': path, ...body!});
      if (submissions.length == 1) return first.future;
      return {'ok': true};
    }
    final result = await super.call(path, body);
    if (path == '/local/codex%3Atwo') {
      result['id'] = 'codex:two';
      result['nativeId'] = 'two';
    }
    return result;
  }
}

class FirstMessageApi extends FakeApi {
  final submissions = <Json>[];
  final receiptReads = <String>[];
  bool available = false;
  bool rejected = false;
  bool confirmed = false;
  Completer<void>? firstResponse;
  ApiException? rejection;
  Json? failedReceipt;

  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/sessions') {
      submissions.add(body!);
      if (submissions.length == 1) {
        await firstResponse?.future;
        if (rejection != null) throw rejection!;
        throw rejected
            ? ApiException('桌面未接收首条消息', 409, null, 'failed')
            : ApiException('请求结果未知');
      }
      confirmed = true;
      return {'id': 'codex:one', 'turnId': 'first-turn'};
    }
    if (path.startsWith('/sessions/requests/')) {
      expect(body, isNull);
      receiptReads.add(path.split('/').last);
      if (failedReceipt != null) return failedReceipt;
      if (!available) return {'state': 'missing'};
      confirmed = true;
      return {
        'state': 'done',
        'result': {'id': 'codex:one', 'turnId': 'first-turn'},
      };
    }
    final result = await super.call(path, body);
    if (path == '/local/codex%3Aone' && confirmed) {
      result['events'] = [
        {
          'id': 'actual-user-message',
          'role': 'user',
          'text': submissions.last['prompt'],
          'turnId': 'first-turn',
        },
      ];
    }
    return result;
  }
}

class VariableHistoryApi extends FakeApi {
  bool expanded = false;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    final data = await super.call(path, body);
    if (path.startsWith('/local/')) {
      data['id'] = Uri.decodeComponent(path.substring('/local/'.length));
      data['events'] = List.generate(
        80,
        (i) => {
          'id': 'message-$i',
          'role': 'assistant',
          'time': i,
          'text':
              'Message $i\n${List.filled(i % 5 + 1, 'Long paragraph for layout. ' * 3).join('\n')}',
        },
      );
    }
    if (expanded && path.startsWith('/local/')) {
      data['events'].last['text'] += '\n${'Media finished layout\n' * 50}';
    }
    return data;
  }
}

CollieShell shell(WidgetTester tester) =>
    tester.widget<CollieShell>(find.byType(CollieShell));

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('unknown creation reads exact receipt without posting again', (
    tester,
  ) async {
    final api = FirstMessageApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control'),
      ),
    );
    await tester.pumpAndSettle();
    shell(tester).onCreate();
    await tester.pumpAndSettle();
    shell(tester).draft.text = 'first message';
    expect(await shell(tester).onSend([]), false);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(shell(tester).enabled, false);
    expect(shell(tester).draft.text, 'first message');
    expect(shell(tester).detail?['events'].single['sendStatus'], 'unknown');
    expect(await shell(tester).onSend([]), false);
    api.available = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(api.submissions, hasLength(1));
    expect(api.receiptReads, isNotEmpty);
    expect(api.receiptReads, everyElement(api.submissions.single['requestId']));
    expect(shell(tester).detail?['id'], 'codex:one');
    expect(shell(tester).detail?['events'].single['id'], 'actual-user-message');
    expect(shell(tester).draft.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
    'explicit first-message rejection allows corrected manual retry',
    (tester) async {
      final api = FirstMessageApi()..rejected = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'control'),
        ),
      );
      await tester.pumpAndSettle();
      shell(tester).onCreate();
      await tester.pumpAndSettle();
      shell(tester).draft.text = 'first message';
      expect(await shell(tester).onSend([]), false);
      await tester.pumpAndSettle();
      expect(shell(tester).enabled, true);
      expect(shell(tester).detail?['events'].single['sendStatus'], 'failed');
      expect(shell(tester).draft.text, 'first message');
      shell(tester).draft.text = 'corrected message';
      final sending = shell(tester).onSend([]);
      expect(await sending, true);
      await tester.pumpAndSettle();
      expect(api.submissions, hasLength(2));
      expect(
        api.submissions.last['requestId'],
        api.submissions.first['requestId'],
      );
      expect(api.submissions.last['prompt'], 'corrected message');
      expect(api.receiptReads, isEmpty);
      expect(
        shell(tester).detail?['events'].single['text'],
        'corrected message',
      );
      expect(shell(tester).draft.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );

  for (final fromLedger in [false, true]) {
    testWidgets(
      'first-send image rejection locks only the invalid file (ledger: $fromLedger)',
      (tester) async {
        const code = 'session_create_invalid_image';
        const rawError = 'ffmpeg /private/workspace/input.jpg';
        final api = FirstMessageApi()..firstResponse = Completer<void>();
        if (!fromLedger) {
          api.rejection = ApiException(rawError, 409, code, 'failed', 'bad');
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: fromLedger ? ThemeData.dark() : ThemeData.light(),
            home: Workspace(api: api, role: 'control'),
          ),
        );
        await tester.pumpAndSettle();
        shell(tester).onCreate();
        await tester.pumpAndSettle();
        shell(tester).uploads.addAll([
          {'id': 'bad', 'name': 'bad.jpg', 'image': true},
          {'id': 'good', 'name': 'notes.txt', 'image': false},
        ]);
        final field = find.byType(TextField).last;
        await tester.enterText(field, 'new report');
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await tester.pump();
        expect(find.text('正在发送首条消息…'), findsOneWidget);
        expect(tester.widget<TextField>(field).enabled, false);
        expect(find.text('发送中…'), findsNothing);
        expect(await shell(tester).onSend(['bad', 'good']), false);
        api.firstResponse!.complete();
        await tester.pumpAndSettle();
        if (fromLedger) {
          expect(find.text('正在确认发送结果'), findsOneWidget);
          expect(tester.widget<TextField>(field).enabled, false);
          await tester.tap(find.byTooltip('移除附件 bad.jpg'));
          await tester.pump();
          expect(shell(tester).uploads, hasLength(2));
          api.failedReceipt = {
            'state': 'failed',
            'error': rawError,
            'code': code,
            'attachmentId': 'bad',
          };
          await tester.pump(const Duration(seconds: 2));
          await tester.pumpAndSettle();
        }
        expect(find.text('首条消息未发送'), findsOneWidget);
        expect(find.text('bad.jpg 无法读取，请移除或更换'), findsOneWidget);
        expect(find.textContaining('/private/workspace'), findsNothing);
        expect(tester.widget<TextField>(field).enabled, true);
        await tester.enterText(field, 'corrected report');
        await tester.tap(find.byTooltip('重新发送'));
        await tester.pump();
        expect(await shell(tester).onSend(['bad', 'good']), false);
        expect(api.submissions, hasLength(1));
        await tester.tap(find.byTooltip('移除附件 bad.jpg'));
        await tester.pumpAndSettle();
        expect(find.text('可重新发送。'), findsOneWidget);
        await tester.tap(find.byTooltip('重新发送'));
        await tester.pumpAndSettle();
        expect(api.submissions, hasLength(2));
        expect(
          api.submissions.last['requestId'],
          api.submissions.first['requestId'],
        );
        expect(api.submissions.last['attachments'], ['good']);
        expect(api.submissions.last['prompt'], 'corrected report');
        expect(find.text('首条消息未发送'), findsNothing);
        expect(shell(tester).detail?['id'], 'codex:one');
        expect(shell(tester).uploads, isEmpty);
        await tester.pumpWidget(const SizedBox());
        api.close();
      },
    );
  }

  testWidgets(
    'legacy failure retains its attachment and permits a manual retry',
    (tester) async {
      final api = FirstMessageApi()
        ..rejection = ApiException(
          'Command failed: /usr/bin/ffmpeg /private/report.png',
          409,
          'session_create_prepare',
          'failed',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'control'),
        ),
      );
      await tester.pumpAndSettle();
      shell(tester).onCreate();
      await tester.pumpAndSettle();
      shell(
        tester,
      ).uploads.add({'id': 'photo', 'name': 'photo.jpg', 'image': true});
      await tester.enterText(find.byType(TextField).last, 'review');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.text('请检查附件或电脑服务后重试。'), findsOneWidget);
      expect(find.textContaining('/private'), findsNothing);
      await tester.tap(find.byTooltip('重新发送'));
      await tester.pumpAndSettle();
      expect(api.submissions.last['attachments'], ['photo']);
      expect(api.submissions, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );

  testWidgets(
    'ack consumes composing snapshot and persisted draft immediately',
    (tester) async {
      final api = SubmissionApi();
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
      shell(tester).draft.value = const TextEditingValue(
        text: 'mit呢',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      );
      await tester.pump(const Duration(milliseconds: 350));
      final sending = shell(tester).onSend([]);
      api.acknowledgement.complete({'ok': true, 'turnId': 'actual-turn'});
      expect(await sending, true);
      await tester.pumpAndSettle();
      expect(shell(tester).draft.text, isEmpty);
      expect(shell(tester).draft.value.composing, TextRange.empty);
      final stored = await const FlutterSecureStorage().read(
        key: 'workspace-drafts:${api.base}',
      );
      expect(jsonDecode(stored!).containsKey('codex:one'), false);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );

  testWidgets('delayed ack preserves a different newly written draft', (
    tester,
  ) async {
    final api = SubmissionApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control', initialSession: 'codex:one'),
      ),
    );
    await tester.pumpAndSettle();
    shell(tester).draft.text = 'submitted';
    final sending = shell(tester).onSend([]);
    shell(tester).draft.text = 'new unsent text';
    api.acknowledgement.complete({'ok': true});
    expect(await sending, true);
    await tester.pumpAndSettle();
    expect(shell(tester).draft.text, 'new unsent text');
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
    'unknown result retains draft until exact server receipt arrives',
    (tester) async {
      final api = SubmissionApi();
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
      shell(tester).draft.text = 'result unknown';
      final sending = shell(tester).onSend([]);
      api.acknowledgement.completeError(ApiException('发送结果未知', 504));
      expect(await sending, false);
      await tester.pumpAndSettle();
      expect(shell(tester).draft.text, 'result unknown');
      api.confirmed = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(shell(tester).draft.text, isEmpty);
      expect(api.submissions, 1);
      expect(api.submittedRequest, isNotNull);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );

  for (final timeoutAfterSwitch in [false, true]) {
    testWidgets('manual retry keeps the original request after switching chats '
        '(timeout after switch: $timeoutAfterSwitch)', (tester) async {
      final api = ConversationSendApi();
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
      shell(tester).draft.text = 'same text in both chats';
      final sending = shell(tester).onSend([]);
      if (timeoutAfterSwitch) {
        shell(tester).onOpen('codex:two');
        await tester.pumpAndSettle();
      }
      api.first.completeError(ApiException('发送超时', 504));
      expect(await sending, false);
      if (!timeoutAfterSwitch) shell(tester).onOpen('codex:two');
      await tester.pumpAndSettle();
      shell(tester).draft.text = 'same text in both chats';
      expect(await shell(tester).onSend([]), true);
      await tester.pumpAndSettle();
      shell(tester).onOpen('codex:one');
      await tester.pumpAndSettle();
      expect(shell(tester).draft.text, 'same text in both chats');
      final events = shell(tester).detail?['events'] as List;
      expect(events.where((e) => e['sendStatus'] == 'unknown'), hasLength(1));
      expect(api.submissions, hasLength(2));
      final a = api.submissions.first['requestId'];
      expect(api.submissions[1]['requestId'], isNot(a));
      expect(await shell(tester).onSend([]), true);
      expect(api.submissions.last['requestId'], a);
      expect(api.submissions.last['path'], '/desktop/one');
      await tester.pumpWidget(const SizedBox());
      api.close();
    });
  }

  testWidgets('a late send receipt consumes only the submitted selection', (
    tester,
  ) async {
    final api = SubmissionApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control', initialSession: 'codex:one'),
      ),
    );
    await tester.pumpAndSettle();
    shell(tester).uploads.add({'id': 'a', 'name': 'a.txt'});
    await tester.enterText(find.byType(TextField).last, 'with attachment');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    api.acknowledgement.completeError(ApiException('发送超时', 504));
    await tester.pumpAndSettle();
    expect(find.byTooltip('移除附件 a.txt'), findsOneWidget);
    shell(tester).uploads.add({'id': 'b', 'name': 'b.txt'});
    api.confirmed = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(api.submissions, 1);
    expect(shell(tester).draft.text, isEmpty);
    expect(find.byTooltip('移除附件 a.txt'), findsNothing);
    expect(find.byTooltip('移除附件 b.txt'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
    'switching back cannot submit a second write while the first is in flight',
    (tester) async {
      final api = ConversationSendApi();
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
      shell(tester).uploads.add({'id': 'a', 'name': 'a.txt'});
      await tester.enterText(find.byType(TextField).last, 'in flight');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      for (final id in ['codex:two', 'codex:one']) {
        shell(tester).onOpen(id);
        await tester.pumpAndSettle();
      }
      expect(shell(tester).busy, true);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '发送',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(await shell(tester).onSend(['a']), false);
      expect(api.submissions, hasLength(1));

      shell(tester).onOpen('codex:two');
      await tester.pumpAndSettle();
      shell(tester).uploads.add({'id': 'a', 'name': 'selection-in-B.txt'});
      api.first.complete({'ok': true});
      await tester.pumpAndSettle();
      expect(find.byTooltip('移除附件 selection-in-B.txt'), findsOneWidget);
      expect(api.submissions, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );

  testWidgets(
    'long history opens at actual latest and user history survives refresh',
    (tester) async {
      final api = VariableHistoryApi();
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
      expect(shell(tester).scroll.position.extentAfter, lessThan(1));
      api.expanded = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(shell(tester).scroll.position.extentAfter, lessThan(1));
      await tester.drag(find.byType(ListView).last, const Offset(0, 650));
      await tester.pumpAndSettle();
      final before = shell(tester).scroll.offset;
      expect(shell(tester).scroll.position.extentAfter, greaterThan(300));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(shell(tester).scroll.offset, closeTo(before, 1));
      shell(tester).onOpen('codex:two');
      await tester.pumpAndSettle();
      expect(shell(tester).scroll.position.extentAfter, lessThan(1));
      shell(tester).onOpen('codex:one');
      await tester.pumpAndSettle();
      expect(shell(tester).scroll.position.extentAfter, lessThan(1));
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('offline cached long conversation opens at latest', (
    tester,
  ) async {
    final api = OfflineApi();
    FlutterSecureStorage.setMockInitialValues({
      'workspace-cache:${api.base}': jsonEncode({
        'sessions': [
          {'id': 'codex:cached', 'title': 'Cached', 'agent': 'Codex'},
        ],
        'projects': [],
        'details': {
          'codex:cached': {
            'id': 'codex:cached',
            'title': 'Cached',
            'agent': 'Codex',
            'events': List.generate(
              60,
              (i) => {
                'id': '$i',
                'role': 'assistant',
                'time': i,
                'text': 'Cached message $i\n${'Long history ' * 30}',
              },
            ),
          },
        },
      }),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(
          api: api,
          role: 'control',
          initialSession: 'codex:cached',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(shell(tester).online, false);
    expect(shell(tester).scroll.position.extentAfter, lessThan(1));
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
    'receipt after navigation consumes old saved draft without changing new chat',
    (tester) async {
      final api = SubmissionApi();
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
      shell(tester).draft.text = 'submitted in previous chat';
      final sending = shell(tester).onSend([]);
      shell(tester).onHome();
      await tester.pump();
      shell(tester).onCreate();
      await tester.pump();
      shell(tester).draft.text = 'new chat draft';
      api.acknowledgement.complete({'ok': true});
      expect(await sending, true);
      await tester.pumpAndSettle();
      expect(shell(tester).draft.text, 'new chat draft');
      final stored = await const FlutterSecureStorage().read(
        key: 'workspace-drafts:${api.base}',
      );
      expect(jsonDecode(stored!).containsKey('codex:one'), false);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
