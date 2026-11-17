import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/process_record.dart';

void main() {
  test('tool images use only explicit supported media', () {
    expect(
      toolImageReferences({
        'role': 'tool',
        'text': '![secret](/secret.png)',
        'media': [
          '/a.png',
          '/a.png',
          'https://evil.test/a.png',
          '/report.pdf',
          'gcollie-resource:${'a' * 32}',
        ],
      }),
      ['/a.png', 'gcollie-resource:${'a' * 32}'],
    );
    expect(
      toolImageReferences({
        'role': 'reasoning',
        'media': ['/a.png'],
      }),
      isEmpty,
    );
  });
  testWidgets(
    'tool images collapse by default and toggle with the tool row at its left edge',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProcessRecord(
              record: {
                'role': 'tool',
                'name': 'view_image',
                'status': 'completed',
                'media': ['/one.png', '/two.png'],
                'text': 'view result',
              },
              media: Text('image fixture'),
            ),
          ),
        ),
      );
      expect(find.text('已查看 2 张图像'), findsOneWidget);
      expect(find.text('image fixture'), findsNothing);
      expect(find.byTooltip('复制工具记录'), findsNothing);
      await tester.tap(find.text('已查看 2 张图像'));
      await tester.pump();
      expect(find.text('image fixture'), findsOneWidget);
      expect(find.byTooltip('复制工具记录'), findsNothing);
      expect(
        tester.getTopLeft(find.text('image fixture')).dx,
        tester.getTopLeft(find.byType(ProcessRecord)).dx,
      );
      await tester.tap(find.text('已查看 2 张图像'));
      await tester.pump();
      expect(find.text('image fixture'), findsNothing);
      expect(find.byTooltip('复制工具记录'), findsNothing);
    },
  );
  testWidgets(
    'mixed command and image have independent left-aligned disclosures',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProcessRecord(
              record: {
                'role': 'tool',
                'name': 'exec',
                'status': 'completed',
                'commands': [
                  {
                    'command': 'printf OK',
                    'output': 'terminal fixture',
                    'exitCode': 0,
                  },
                ],
                'media': ['/one.png'],
                'text': 'wrapper output',
              },
              media: Text('image fixture'),
            ),
          ),
        ),
      );
      final command = find.text('已运行 printf OK');
      final image = find.text('已查看 1 张图像');
      final commandBody = find.textContaining('terminal fixture');
      final imageBody = find.text('image fixture');
      expect(
        tester.getTopLeft(command).dy,
        lessThan(tester.getTopLeft(image).dy),
      );
      expect(find.byIcon(Icons.terminal), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(commandBody, findsNothing);
      expect(imageBody, findsNothing);
      await tester.tap(image);
      await tester.pump();
      expect(imageBody, findsOneWidget);
      expect(commandBody, findsNothing);
      expect(
        tester.getTopLeft(imageBody).dx,
        tester.getTopLeft(find.byType(ProcessRecord)).dx,
      );
      await tester.tap(command);
      await tester.pump();
      expect(imageBody, findsOneWidget);
      expect(commandBody, findsOneWidget);
      await tester.tap(image);
      await tester.pump();
      expect(imageBody, findsNothing);
      expect(commandBody, findsOneWidget);
      await tester.tap(command);
      await tester.pump();
      expect(commandBody, findsNothing);
    },
  );

  testWidgets(
    'pending failed and unknown image results do not claim completed viewing',
    (tester) async {
      for (final status in ['pending', 'failed', 'unknown', 'submitted']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProcessRecord(
                record: {
                  'role': 'tool',
                  'status': status,
                  'media': ['/a.png'],
                },
              ),
            ),
          ),
        );
        expect(find.textContaining('已查看'), findsNothing);
      }
    },
  );

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
