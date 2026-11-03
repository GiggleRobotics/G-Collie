import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/request_input.dart';
import 'package:g_collie_flutter/api.dart';

void main() {
  testWidgets(
    'multi-select submits native JSON array without duplicate custom field',
    (tester) async {
      Json? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestInputCard(
              enabled: true,
              request: {
                'id': 'multi',
                'kind': 'question',
                'params': {
                  'questions': [
                    {
                      'id': 'q',
                      'question': '选择颜色',
                      'multiSelect': true,
                      'options': [
                        {'label': '蓝'},
                        {'label': '绿'},
                      ],
                    },
                  ],
                },
              },
              onSubmit: (answer) async {
                result = answer;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('蓝'));
      await tester.pump();
      await tester.tap(find.text('绿'));
      await tester.pump();
      expect(find.text('填写其他回答'), findsNothing);
      await tester.tap(find.text('提交回答'));
      await tester.pump();
      expect(result?['answers']['q'], '["蓝","绿"]');
    },
  );

  final request = <String, dynamic>{
    'id': 'q1',
    'kind': 'question',
    'params': {
      'questions': [
        {
          'id': 'mode',
          'question': '请选择输出方式',
          'options': [
            {'label': '简洁', 'description': '只显示必要内容'},
            {'label': '详细', 'description': '包含完整步骤'},
          ],
        },
      ],
    },
  };
  testWidgets(
    'approval keeps command folded and submits only the selected decision',
    (tester) async {
      Json? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RequestInputCard(
                request: {
                  'id': 'approval1',
                  'kind': 'approval',
                  'params': {
                    'reason': '请确认本次操作',
                    'command': 'printf demo',
                    'availableDecisions': ['accept', 'decline'],
                  },
                },
                enabled: true,
                onSubmit: (value) async {
                  submitted = value;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('printf demo'), findsNothing);
      await tester.tap(find.text('查看将执行的命令'));
      await tester.pumpAndSettle();
      expect(find.text('printf demo'), findsOneWidget);
      await tester.tap(find.text('批准一次'));
      await tester.pumpAndSettle();
      expect(submitted, {'decision': 'accept'});
    },
  );
  testWidgets(
    'approval does not offer a decision absent from native permissions',
    (tester) async {
      Json? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestInputCard(
              request: {
                'id': 'approval2',
                'kind': 'approval',
                'params': {
                  'availableDecisions': ['decline'],
                },
              },
              enabled: true,
              onSubmit: (value) async {
                submitted = value;
                return true;
              },
            ),
          ),
        ),
      );
      expect(find.text('批准一次'), findsNothing);
      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();
      expect(submitted, {'decision': 'decline'});
    },
  );
  testWidgets(
    'selecting an answer shows its state and submits without a duplicate field',
    (tester) async {
      Json? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RequestInputCard(
                request: request,
                enabled: true,
                onSubmit: (value) async {
                  submitted = value;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('简洁'));
      await tester.pump();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      await tester.tap(find.text('提交回答'));
      await tester.pumpAndSettle();
      expect(submitted?['answers'], {'mode': '简洁'});
    },
  );
  testWidgets(
    'custom answer is optional to open and required before submitting',
    (tester) async {
      Json? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RequestInputCard(
                request: request,
                enabled: true,
                onSubmit: (value) async {
                  submitted = value;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('填写其他回答'));
      await tester.pump();
      expect(find.byType(TextFormField), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextFormField), '只列出变更');
      await tester.pump();
      expect(find.text('填写其他回答'), findsNothing);
      await tester.tap(find.text('简洁'));
      await tester.pump();
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('填写其他回答'));
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '只列出变更',
      );
      await tester.ensureVisible(find.text('提交回答'));
      await tester.tap(find.text('提交回答'));
      await tester.pumpAndSettle();
      expect(submitted?['answers'], {'mode': '只列出变更'});
    },
  );
  testWidgets(
    'secret reveal and cancel never put input in a conversation draft',
    (tester) async {
      Json? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RequestInputCard(
                request: {
                  'id': 'secret1',
                  'kind': 'secret',
                  'params': {'prompt': '请输入演示口令'},
                },
                enabled: true,
                onSubmit: (value) async {
                  submitted = value;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.enterText(field, 'demo-value');
      await tester.pump();
      await tester.tap(find.byTooltip('显示内容'));
      await tester.pump();
      expect(tester.widget<TextField>(field).obscureText, isFalse);
      await tester.tap(find.text('取消本次请求'));
      await tester.pumpAndSettle();
      expect(submitted, {'value': ''});
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(tester.widget<TextField>(field).obscureText, isTrue);
    },
  );
}
