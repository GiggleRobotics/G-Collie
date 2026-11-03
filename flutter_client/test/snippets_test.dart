import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/snippets.dart';

void main() {
  testWidgets('snippet persists and reopens without sending', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: SnippetLibrary()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '先列结论再给验证步骤');
    await tester.pump();
    await tester.tap(find.text('保存到片段库'));
    await tester.pumpAndSettle();
    expect(find.text('已保存 1 / 100'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: SnippetLibrary()));
    await tester.pumpAndSettle();
    expect(find.text('先列结论再给验证步骤'), findsOneWidget);
    await tester.tap(find.byTooltip('删除片段'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('已保存 1 / 100'), findsOneWidget);
  });
}
