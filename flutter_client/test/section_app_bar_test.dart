import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/section_app_bar.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('section titles share geometry in $brightness', (tester) async {
      for (final title in ['项目管理', '用量统计', '定时消息', '下载内容', '故障诊断', '添加定时消息']) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              appBar: SectionAppBar(title: Text(title)),
              body: const SizedBox(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text(title)).dx, 65);
        expect(tester.getSize(find.byType(AppBar)).height, 60);
        expect(find.byTooltip('返回'), findsOneWidget);
      }
    });
  }
}
