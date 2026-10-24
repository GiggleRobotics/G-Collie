import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/quota_notice.dart';

class QuotaApi extends CollieApi {
  int used = 100;
  QuotaApi() : super(Uri.parse('http://localhost:4310'));
  @override
  Future<dynamic> call(String path, [Json? body]) async => {
    'codexAccount': {
      'accountKey': 'test-account',
      'limits': [
        {
          'id': 'codex',
          'windows': [
            {
              'windowMinutes': 300,
              'usedPercent': used,
              'resetsAt':
                  DateTime.now()
                      .add(const Duration(hours: 2))
                      .millisecondsSinceEpoch ~/
                  1000,
            },
            {'windowMinutes': 10080, 'usedPercent': 22},
          ],
        },
      ],
      'resetCredits': {'availableCount': 2, 'credits': []},
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real quota snapshot blocks only when exhausted and refresh recovers',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = QuotaApi();
      bool? blocked;
      String error = '';
      Widget page() => MaterialApp(
        home: Scaffold(
          body: CodexQuotaNotice(
            api: api,
            readOnly: false,
            online: true,
            error: error,
            onBlocked: (v) => blocked = v,
            onRefresh: () async {},
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(blocked, true);
      expect(find.text('剩余 0%'), findsOneWidget);
      expect(find.text('剩余 78%'), findsOneWidget);
      expect(find.text('重置额度'), findsOneWidget);
      api.used = 10;
      error = 'refresh';
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(blocked, false);
      expect(find.text('重置额度'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
