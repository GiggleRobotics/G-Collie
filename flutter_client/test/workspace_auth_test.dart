import 'package:flutter/material.dart';
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

void main() {
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
    api.close();
  });
}
