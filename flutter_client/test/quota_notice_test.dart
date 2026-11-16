import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/quota_notice.dart';

class LimitsApi extends CollieApi {
  LimitsApi() : super(Uri.parse('http://localhost:4310'));
  bool fail = false;
  int used = 30;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (fail) throw ApiException('temporary quota lookup failure', 503);
    return {
      'codexAccount': {
        'limits': [
          {
            'id': 'codex',
            'windows': [
              {
                'windowMinutes': 300,
                'usedPercent': used,
                'resetsAt': 2000000000,
              },
            ],
          },
        ],
      },
    };
  }
}

void main() {
  testWidgets(
    'background quota lookup failure never expands quota/reset panel',
    (tester) async {
      final api = LimitsApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CodexQuotaNotice(
              api: api,
              readOnly: false,
              online: true,
              error: '',
              onBlocked: (_) {},
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('5 小时限额'), findsNothing);
      api.fail = true;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('5 小时限额'), findsNothing);
      expect(find.text('刷新额度'), findsNothing);
      expect(find.text('暂时无法查询额度'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'first lookup failure stays quiet while actual exhaustion is shown',
    (tester) async {
      final api = LimitsApi()..fail = true;
      addTearDown(api.close);
      bool blocked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CodexQuotaNotice(
              api: api,
              readOnly: true,
              online: true,
              error: '',
              onBlocked: (v) => blocked = v,
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时无法查询额度'), findsNothing);
      expect(blocked, false);
      api.fail = false;
      api.used = 100;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('5 小时限额'), findsOneWidget);
      expect(blocked, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('explicit exhaustion error stays actionable when lookup fails', (
    tester,
  ) async {
    final api = LimitsApi()..fail = true;
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodexQuotaNotice(
            api: api,
            readOnly: true,
            online: true,
            error: 'usage_limit_exceeded',
            onBlocked: (_) {},
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法查询额度'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
