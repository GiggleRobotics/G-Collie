import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/ui.dart';
import 'package:g_collie_flutter/computers.dart';
import 'package:g_collie_flutter/main.dart';
import 'workspace_test.dart' show FakeApi;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsApi extends CollieApi {
  SettingsApi() : super(Uri.parse('http://100.84.91.5:4310'));
  @override
  Future<dynamic> call(String p, [Json? b]) async => p == '/network'
      ? {
          'computerName': 'Test PC',
          'embedded': {'address': 'http://100.84.91.5:4310'},
          'addresses': ['http://192.168.1.2:4310'],
        }
      : {
          'checks': [
            {'name': '电脑服务', 'status': '正常'},
          ],
        };
}

class SecureApi extends FakeApi {
  Json? answer;
  SecureApi() {
    agent = 'Hermes';
    pending = {
      'id': 'secure-test',
      'kind': 'secret',
      'params': {'command': 'sudo true', 'prompt': '请输入电脑密码'},
    };
  }
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/hermes/one') {
      answer = body;
      pending = null;
      return {'ok': true};
    }
    return super.call(path, body);
  }
}

void main() {
  testWidgets(
    'connection settings handles real diagnostics shape without null or experimental switch',
    (tester) async {
      final api = SettingsApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsBody(api: api, role: 'control', title: '电脑与连接'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('服务：正常'), findsOneWidget);
      expect(
        find.textContaining('服务地址：http://100.84.91.5:4310'),
        findsOneWidget,
      );
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('实验性'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('cancel add computer pops only its sheet and preserves parent', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('原会话'),
                TextButton(
                  onPressed: () => collieSheet<void>(
                    context,
                    '添加电脑',
                    (_) => AddComputerPane(
                      computers: ComputerStore(const FlutterSecureStorage()),
                    ),
                  ),
                  child: const Text('添加'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消并返回切换电脑'));
    await tester.pumpAndSettle();
    expect(find.text('原会话'), findsOneWidget);
    expect(find.byType(AddComputerPane), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Hermes secure request submits through phone with masked non-chat input',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = SecureApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(
            api: api,
            role: 'control',
            initialSession: 'codex:one',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('需要安全输入'), findsOneWidget);
      final field = find.byKey(const ValueKey('secret:secure-test'));
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.enterText(field, 'test-password');
      await tester.ensureVisible(find.text('提交'));
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      expect(api.answer?['value'], 'test-password');
      expect(api.answer?['pendingId'], 'secure-test');
      expect(find.text('test-password'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
