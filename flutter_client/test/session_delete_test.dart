import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/session_delete.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'workspace_test.dart' show FakeApi;

class EndedHistoryDeleteApi extends FakeApi {
  final bool allowed;
  int checks = 0, deleteCalls = 0;
  EndedHistoryDeleteApi(this.allowed) {
    status = 'unknown';
    agent = 'Hermes';
  }
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path.endsWith('/delete-eligibility')) {
      checks++;
      return {
        'supported': true,
        'allowed': allowed,
        'reason': allowed ? '' : '来源实时状态未知，暂不可删除',
      };
    }
    if (path.endsWith('/delete')) {
      deleteCalls++;
      return {
        'ok': true,
        'deleted': true,
        'deletedIds': ['codex:one'],
      };
    }
    return super.call(path, body);
  }
}

void main() {
  for (final allowed in [true, false]) {
    testWidgets(
      'unknown historical detail follows fresh server ${allowed ? 'allow' : 'deny'}',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final api = EndedHistoryDeleteApi(allowed);
        addTearDown(api.close);
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
        expect(
          tester
              .widget<CollieShell>(find.byType(CollieShell))
              .detail?['status'],
          'unknown',
        );
        final dynamic shell = tester.state(find.byType(CollieShell));
        shell.deleteSession();
        await tester.pumpAndSettle();
        expect(api.checks, 1);
        final confirm = tester.widget<FilledButton>(
          find.byType(FilledButton).last,
        );
        if (allowed) {
          expect(confirm.onPressed, isNotNull);
          await tester.tap(find.text('确认删除'));
          await tester.pumpAndSettle();
          expect(api.deleteCalls, 1);
        } else {
          expect(confirm.onPressed, isNull);
          expect(find.text('来源实时状态未知，暂不可删除'), findsOneWidget);
          await tester.tap(find.text('确认删除'));
          await tester.pumpAndSettle();
          expect(api.deleteCalls, 0);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  Future<void> show(
    WidgetTester t, {
    required Future<Json> Function(String) remove,
    Future<Json> Function()? eligibility,
    Future<void> Function(List<String>)? deleted,
    String? blocked,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionDeletePanel(
            key: UniqueKey(),
            detail: {'id': 'hermes:target', 'title': '隔离测试', 'agent': 'Hermes'},
            computer: 'QA',
            blocked: blocked,
            eligibility:
                eligibility ?? () async => {'supported': true, 'allowed': true},
            remove: remove,
            onDeleted: deleted ?? (_) async {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('unknown write cannot retry even after a local refresh', (
    t,
  ) async {
    var calls = 0;
    await show(
      t,
      remove: (_) async {
        calls++;
        throw ApiException('超时');
      },
    );
    await t.tap(find.text('确认删除'));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('结果未知'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(find.text('重新检查删除条件'), findsNothing);
  });
  testWidgets(
    'deterministic rejection requires fresh eligibility and retains history',
    (t) async {
      var checks = 0, calls = 0;
      await show(
        t,
        eligibility: () async {
          checks++;
          return {'allowed': true};
        },
        remove: (_) async {
          calls++;
          throw ApiException('状态变化', 409, 'state_changed', 'failed');
        },
      );
      await t.tap(find.text('确认删除'));
      await t.pumpAndSettle();
      expect(find.textContaining('会话已保留'), findsOneWidget);
      expect(calls, 1);
      await t.tap(find.text('重新检查删除条件'));
      await t.pumpAndSettle();
      expect(checks, 2);
      expect(calls, 1);
    },
  );
  testWidgets(
    'unsupported and local running restriction never invoke deletion',
    (t) async {
      var calls = 0;
      await show(
        t,
        blocked: '执行中禁删',
        remove: (_) async {
          calls++;
          return {};
        },
      );
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, 0);
      await show(
        t,
        eligibility: () async => {
          'allowed': false,
          'supported': false,
          'reason': '当前未适配',
        },
        remove: (_) async {
          calls++;
          return {};
        },
      );
      expect(find.text('当前未适配'), findsOneWidget);
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, 0);
    },
  );
  testWidgets(
    'confirmed deletion passes lineage ids and cannot resend on cache failure',
    (t) async {
      var calls = 0;
      List<String>? removed;
      await show(
        t,
        remove: (_) async {
          calls++;
          return {
            'ok': true,
            'deleted': true,
            'deletedIds': ['hermes:target', 'hermes:old'],
          };
        },
        deleted: (ids) async {
          removed = ids;
          throw Exception('local cache');
        },
      );
      await t.tap(find.text('确认删除'));
      await t.pumpAndSettle();
      expect(removed, ['hermes:target', 'hermes:old']);
      expect(calls, 1);
      expect(find.textContaining('电脑已确认删除'), findsOneWidget);
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );
}
