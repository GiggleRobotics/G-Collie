import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/process_record.dart';

void main() {
  for (final role in ['tool', 'reasoning']) {
    testWidgets('$role detail and copy belong to the assistant left edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ProcessRecord(
                record: {
                  'role': role,
                  'input': 'printf OK',
                  'text': 'Result',
                  'status': 'completed',
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      final detail = find.byType(SelectableText);
      final copy = find.byTooltip('复制工具记录');
      expect(tester.getTopLeft(detail).dx, 32);
      expect(
        tester.getTopLeft(copy).dx,
        greaterThan(tester.getTopLeft(detail).dx),
      );
      expect(
        tester.getBottomRight(copy).dy,
        lessThanOrEqualTo(tester.getTopLeft(detail).dy),
      );
      expect(tester.takeException(), isNull);
    });
  }
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
  testWidgets('empty public summary still shows a completed thinking marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProcessRecord(
            record: {'role': 'reasoning', 'status': 'completed', 'text': ''},
          ),
        ),
      ),
    );
    expect(find.text('已思考'), findsOneWidget);
    await tester.tap(find.text('已思考'));
    await tester.pump();
    expect(find.text('助手未提供公开思考摘要'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });
}
