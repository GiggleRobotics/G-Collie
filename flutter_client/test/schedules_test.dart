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

void main() {
  testWidgets(
    'alarm can save a single character into a new session without selecting history',
    (tester) async {
      tester.view.physicalSize=const Size(400,900);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final api = ScheduleApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SchedulePreview(sessions: const [], api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建定时消息'));
      await tester.pumpAndSettle();
      expect(find.text('新建会话（默认）'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.text('保存定时消息'));
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
