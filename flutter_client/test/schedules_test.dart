import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/schedules.dart';

class ScheduleApi extends CollieApi {
  ScheduleApi() : super(Uri.parse('http://localhost:4310'));
  final List<Json> writes = [];
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (body == null) return {'tasks': []};
    writes.add(body);
    return {'ok': true};
  }
}

class RecoveringScheduleApi extends ScheduleApi {
  bool fail = true;
  Completer<dynamic>? initial;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/schedules' && body == null) {
      if (initial != null) return initial!.future;
      if (fail) throw ApiException('测试连接中断');
    }
    return super.call(path, body);
  }
}

class ExistingScheduleApi extends ScheduleApi {
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/schedules' && body == null) {
      return {
        'tasks': [
          {
            'id': 'qa-task',
            'time': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
            'interval': 0,
            'enabled': true,
            'status': 'pending',
            'text': '已有任务',
            'session': 'new',
          },
        ],
      };
    }
    return super.call(path, body);
  }
}

void main() {
  testWidgets('read-only schedules retain list and expose no write controls', (
    tester,
  ) async {
    final api = ExistingScheduleApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePreview(sessions: const [], api: api, enabled: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已有任务'), findsOneWidget);
    expect(find.text('当前连接仅可查看定时任务'), findsOneWidget);
    expect(find.text('安排下一条消息'), findsNothing);
    expect(find.byTooltip('新建定时任务'), findsNothing);
    expect(find.text('编辑'), findsNothing);
    expect(find.text('取消任务'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(api.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'permission revoked while editing retains input and prevents save',
    (tester) async {
      final api = ScheduleApi();
      bool allowed = true;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SchedulePreview(
            sessions: const [],
            api: api,
            canEdit: () => allowed,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建定时任务'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保留权限撤销前输入');
      allowed = false;
      await tester.tap(find.text('保存定时任务'));
      await tester.pumpAndSettle();
      expect(find.text('当前连接仅可查看定时任务，未保存'), findsOneWidget);
      expect(find.text('保留权限撤销前输入'), findsOneWidget);
      expect(api.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'permission revoked during cancellation confirmation prevents write',
    (tester) async {
      final api = ExistingScheduleApi();
      bool allowed = true;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SchedulePreview(
            sessions: const [],
            api: api,
            canEdit: () => allowed,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消任务'));
      await tester.pumpAndSettle();
      allowed = false;
      await tester.tap(find.text('确认取消'));
      await tester.pumpAndSettle();
      expect(api.writes, isEmpty);
      expect(find.text('已有任务'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'schedule loading and failure do not masquerade as empty; retry clears error',
    (tester) async {
      final api = RecoveringScheduleApi()..initial = Completer<dynamic>();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SchedulePreview(sessions: const [], api: api),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('还没有定时任务'), findsNothing);
      api.initial!.completeError(ApiException('测试连接中断'));
      api.initial = null;
      await tester.pumpAndSettle();
      expect(find.textContaining('定时任务加载失败'), findsOneWidget);
      expect(find.text('安排下一条消息'), findsNothing);
      expect(find.text('还没有定时任务'), findsNothing);
      api.fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.textContaining('测试连接中断'), findsNothing);
      expect(find.text('还没有定时任务'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'alarm can save a single character into a new session without selecting history',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ScheduleApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SchedulePreview(sessions: const [], api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建定时任务'));
      await tester.pumpAndSettle();
      expect(find.text('新建会话（默认）'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.text('保存定时任务'));
      await tester.pumpAndSettle();
      expect(api.writes.single['session'], 'new');
      expect(api.writes.single['text'], '1');
      expect(
        api.writes.single['time'],
        greaterThan(DateTime.now().millisecondsSinceEpoch),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
