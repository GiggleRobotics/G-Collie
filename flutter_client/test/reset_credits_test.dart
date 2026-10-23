import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/reset_credits.dart';

class ResetApi extends CollieApi {
  final List<Json> calls = [];
  bool fail = true;
  ResetApi() : super(Uri.parse('http://localhost:4310'));
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    calls.add(body!);
    if (fail) throw ApiException('timeout');
    return {'outcome': 'alreadyRedeemed'};
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final account = <String, dynamic>{
    'accountKey': 'a',
    'accountLabel': 'test@example.com',
    'resetCredits': {'availableCount': 2, 'credits': null},
  };
  testWidgets(
    'cancel never consumes; retry reuses key and refreshes after success',
    (tester) async {
      final api = ResetApi();
      addTearDown(api.close);
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResetCredits(
              account: account,
              api: api,
              onRefresh: () async {
                refreshes++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用重置卡'));
      await tester.pumpAndSettle();
      expect(find.textContaining('test@example.com'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      await tester.tap(find.text('使用重置卡'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用 1 张并重置'));
      await tester.pumpAndSettle();
      expect(api.calls, hasLength(1));
      expect(find.textContaining('timeout'), findsOneWidget);
      api.fail = false;
      await tester.tap(find.text('重试原重置操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用 1 张并重置'));
      await tester.pumpAndSettle();
      expect(api.calls, hasLength(2));
      expect(api.calls[0]['idempotencyKey'], api.calls[1]['idempotencyKey']);
      expect(refreshes, 1);
      expect(find.text('本次重置已完成'), findsOneWidget);
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    },
  );
  testWidgets('read-only and unknown card count cannot consume', (
    tester,
  ) async {
    final api = ResetApi();
    addTearDown(api.close);
    for (final value in [
      account,
      <String, dynamic>{'accountKey': 'a'},
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResetCredits(
              key: UniqueKey(),
              account: value,
              api: api,
              readOnly: true,
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    }
    expect(api.calls, isEmpty);
  });
}
