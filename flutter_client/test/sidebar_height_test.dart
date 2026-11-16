import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/main.dart';
import 'workspace_test.dart' show FakeApi;

class SidebarHeightApi extends FakeApi {
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    final result = await super.call(path, body);
    if (path == '/local') {
      result['sessions'] = [
        for (var i = 0; i < 18; i++)
          {
            'id': 'codex:other$i',
            'title': '普通记录 $i',
            'agent': 'Codex',
            'project': 'G-Collie',
          },
        {
          'id': 'codex:one',
          'title': 'QA 横屏可访问会话',
          'agent': 'Codex',
          'project': 'G-Collie',
        },
      ];
    }
    return result;
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final search in [false, true]) {
    testWidgets(
      '400dp drawer can ${search ? 'search and ' : ''}scroll to and open QA session',
      (tester) async {
        tester.view.physicalSize = const Size(890, 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = SidebarHeightApi();
        addTearDown(api.close);
        await tester.pumpWidget(
          MaterialApp(
            home: Workspace(api: api, role: 'control'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('打开会话列表'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (search) {
          final field = find.descendant(
            of: find.byType(Drawer),
            matching: find.byType(TextField),
          );
          await tester.enterText(field, 'QA');
          await tester.pumpAndSettle();
        }
        final scrollable = find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first;
        final target = find.text('QA 横屏可访问会话');
        await tester.scrollUntilVisible(
          target,
          160,
          scrollable: scrollable,
          maxScrolls: 30,
        );
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(api.calls, contains('/local/codex%3Aone'));
        expect(find.text('Hello from computer'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
