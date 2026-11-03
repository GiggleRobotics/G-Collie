import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/sketch.dart';

void main() {
  testWidgets('drawing enables attach and undo clears only local drawing', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SketchPage()));
    FilledButton button() =>
        tester.widget(find.widgetWithText(FilledButton, '加入会话附件'));
    expect(button().onPressed, isNull);
    await tester.drag(
      find.byKey(const ValueKey('sketch-pad')),
      const Offset(60, 30),
    );
    await tester.pump();
    expect(button().onPressed, isNotNull);
    await tester.tap(find.byTooltip('撤销笔画'));
    await tester.pump();
    expect(button().onPressed, isNull);
  });
}
