import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/ui.dart';

class UsageApi extends CollieApi {
  UsageApi() : super(Uri.parse('http://localhost:4310'));
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    final counters = {
      'input': 60,
      'output': 5,
      'cached': 20,
      'cacheWrite': 30,
      'total': 65,
      'cacheRate': 1 / 3,
    };
    final agent = {
      'total': counters,
      'today': counters,
      'month': counters,
      'daily': [],
      'monthly': [],
      'sessions': [],
      'projects': [],
      'models': [],
    };
    return {
      'generatedAt': '2026-10-23',
      'timezone': 'CST',
      'agents': {'Codex': agent, 'Claude Code': agent},
      'codexAccount': {
        'limits': [],
        'usage': {'summary': {}, 'dailyUsageBuckets': []},
      },
    };
  }
}

void main() {
  testWidgets(
    'Claude usage tab is visible on phone and does not show Codex account quota',
    (tester) async {
      final api = UsageApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UsagePage(api: api, onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claude Code'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Claude Code · 主会话及子代理日志'), findsOneWidget);
      expect(find.text('Codex 账号额度'), findsNothing);
      expect(find.text('账号总览'), findsNothing);
      expect(find.text('缓存写入 30'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
