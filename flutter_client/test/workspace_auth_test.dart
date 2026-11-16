import 'dart:async';
import 'package:flutter/material.dart';
import 'workspace_test.dart' show FakeApi;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/ui.dart';

class AuthApi extends CollieApi {
  bool revoked = false;
  AuthApi() : super(Uri.parse('http://localhost:4310/'));
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (revoked) throw ApiException('配对已失效', 401);
    if (path == '/auth/status') {
      return {
        'paired': true,
        'device': {'role': 'view'},
      };
    }
    if (path == '/network') return {'computerName': '工作电脑'};
    return {'sessions': [], 'projects': [], 'warnings': []};
  }
}

class ChangingRoleApi extends FakeApi {
  String role = 'control';
  int authCalls = 0;
  bool deny = false;
  Completer<dynamic>? pendingAuth;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/auth/status') {
      authCalls++;
      return pendingAuth?.future ??
          {
            'paired': true,
            'device': {'role': role},
          };
    }
    if (path == '/desktop/one' && deny) throw ApiException('只读设备', 403);
    return super.call(path, body);
  }
}

void main() {
  testWidgets('concurrent permission refreshes share one auth request', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = ChangingRoleApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control', initialSession: 'codex:one'),
      ),
    );
    await tester.pumpAndSettle();
    final count = api.authCalls;
    api.pendingAuth = Completer<dynamic>();
    final dynamic state = tester.state(find.byType(Workspace));
    final Future<void> first = state.refreshRole(force: true);
    final Future<void> second = state.refreshRole(force: true);
    expect(api.authCalls, count + 1);
    api.pendingAuth!.complete({
      'paired': true,
      'device': {'role': 'view'},
    });
    await Future.wait([first, second]);
    await tester.pump();
    expect(tester.widget<CollieShell>(find.byType(CollieShell)).role, 'view');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'online role downgrade refreshes on resume and preserves paired draft',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = ChangingRoleApi();
      addTearDown(api.close);
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
      var shell = tester.widget<CollieShell>(find.byType(CollieShell));
      expect(shell.enabled, true);
      shell.draft.text = '保留草稿';
      final initialCalls = api.authCalls;
      await shell.onRefresh();
      await shell.onRefresh();
      expect(api.authCalls, initialCalls);
      api.role = 'view';
      final dynamic state = tester.state(find.byType(Workspace));
      state.didChangeAppLifecycleState(AppLifecycleState.inactive);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      shell = tester.widget<CollieShell>(find.byType(CollieShell));
      expect(api.authCalls, initialCalls + 1);
      expect(shell.role, 'view');
      expect(shell.enabled, false);
      expect(shell.online, true);
      expect(shell.draft.text, '保留草稿');
      expect(await shell.onSend([]), false);
      expect(api.sent, isNull);
      expect(find.byType(Workspace), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
    },
  );
  testWidgets('403 rechecks real auth status without replaying denied send', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = ChangingRoleApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control', initialSession: 'codex:one'),
      ),
    );
    await tester.pumpAndSettle();
    final initialCalls = api.authCalls;
    api.role = 'view';
    api.deny = true;
    var shell = tester.widget<CollieShell>(find.byType(CollieShell));
    shell.draft.text = '拒绝后保留';
    expect(await shell.onSend([]), false);
    await tester.pumpAndSettle();
    shell = tester.widget<CollieShell>(find.byType(CollieShell));
    expect(api.authCalls, initialCalls + 1);
    expect(shell.role, 'view');
    expect(shell.enabled, false);
    expect(shell.draft.text, '拒绝后保留');
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  });

  testWidgets('revoked pairing exits workspace even while a dialog is open', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = AuthApi();
    final navigator = GlobalKey<NavigatorState>();
    bool invalid = false;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                ctx,
                MaterialPageRoute(
                  builder: (_) => Workspace(
                    api: api,
                    role: 'view',
                    onPairingInvalid: () => invalid = true,
                  ),
                ),
              ),
              child: const Text('配对首页'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('配对首页'));
    await tester.pumpAndSettle();
    showDialog<void>(
      context: navigator.currentState!.overlay!.context,
      builder: (_) => const AlertDialog(title: Text('连接设置')),
    );
    await tester.pumpAndSettle();
    api.revoked = true;
    await tester.widget<CollieShell>(find.byType(CollieShell)).onRefresh();
    await tester.pumpAndSettle();
    expect(invalid, true);
    expect(find.byType(Workspace), findsNothing);
    expect(find.text('配对首页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    api.close();
  });
}
