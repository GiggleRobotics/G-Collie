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
