import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/process_record.dart';

void main() {
  testWidgets(
    'compact row hides output until expanded and stays open after refresh',
    (tester) async {
      final e = <String, dynamic>{
        'id': 'one',
        'role': 'tool',
        'name': 'terminal',
        'input': 'printf OK',
        'text': 'private output',
        'status': 'completed',
        'durationMs': 2100,
      };
      Widget app() => MaterialApp(
        home: Scaffold(
          body: ProcessRecord(key: const ValueKey('one'), record: e),
        ),
      );
      await tester.pumpWidget(app());
      expect(find.text('private output'), findsNothing);
      expect(find.textContaining('已运行 printf OK'), findsOneWidget);
      expect(find.text('2 秒'), findsOneWidget);
      await tester.tap(find.textContaining('已运行 printf OK'));
      await tester.pump();
      expect(find.textContaining('private output'), findsOneWidget);
      e['text'] = 'updated output';
      await tester.pumpWidget(app());
      expect(find.textContaining('updated output'), findsOneWidget);
    },
  );
  testWidgets('missing result and failed result have distinct honest status', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProcessRecord(
            record: {
              'role': 'tool',
              'name': 'terminal',
              'input': 'test',
              'status': 'pending',
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('结果未记录'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProcessRecord(
            record: {
              'role': 'tool',
              'name': 'terminal',
              'input': 'test',
              'status': 'failed',
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('执行失败'), findsOneWidget);
  });
}
