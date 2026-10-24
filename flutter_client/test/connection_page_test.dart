import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/native.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeBridge.channel,
      (_) async => null,
    );
    appTheme.value = ThemeMode.light;
  });
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeBridge.channel,
      null,
    ),
  );
  testWidgets(
    'first launch shows explicit computer address, code and optional phone without a dialog',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await tester.pumpWidget(const CollieApp());
      await tester.pumpAndSettle();
      expect(find.text('连接你的第一台电脑'), findsOneWidget);
      expect(find.text('电脑地址'), findsOneWidget);
      expect(find.text('本手机名称（选填）'), findsOneWidget);
      expect(find.text('配对并连接'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'saved pairing opens cached workspace before a network is available',
    (tester) async {
      const base = 'http://127.0.0.1:4310/';
      FlutterSecureStorage.setMockInitialValues({
        'server': base,
        'cookie:$base': 'device=saved',
        'paired-computers-v1': jsonEncode([
          {'address': base, 'name': '工作电脑', 'role': 'view'},
        ]),
        'workspace-cache:$base': jsonEncode({
          'sessions': [
            {
              'id': 'codex:cached',
              'title': '已缓存会话',
              'agent': 'Codex',
              'project': '项目',
            },
          ],
          'projects': [],
          'details': {},
        }),
      });
      await tester.pumpWidget(const CollieApp());
      await tester.pumpAndSettle();
      expect(find.byType(Workspace), findsOneWidget);
      expect(find.text('连接你的第一台电脑'), findsNothing);
      expect(find.text('已缓存会话'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
