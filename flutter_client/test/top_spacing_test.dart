import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/connection_page.dart' as section;
import 'package:g_collie_flutter/section_app_bar.dart';
import 'workspace_test.dart' show FakeApi;

void main() {
  testWidgets(
    'section consumes status inset once and retains 48dp back target',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(
        const MaterialApp(
          home: section.ConnectionPage(
            appBar: SectionAppBar(primary: false, title: Text('下载内容')),
            body: SizedBox(key: ValueKey('section-body')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('section-body'))).dy,
        24 + 40 + 52,
      );
      expect(
        tester.getSize(find.byTooltip('返回')).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(890, 400),
  ]) {
    testWidgets('conversation starts 8dp below 40dp + 48dp titles at $size', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final api = FakeApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Workspace(
            api: api,
            role: 'view',
            initialData: {
              'online': true,
              'sessions': [],
              'projects': [],
              'detail': {
                'id': 'codex:one',
                'agent': 'Claude Code',
                'status': 'idle',
                'events': [
                  {'role': 'assistant', 'text': '首条消息', 'id': 'first'},
                ],
              },
            },
          ),
        ),
      );
      // Check the seeded first frame before async fixture history replaces it.
      final content = find.byKey(const ValueKey('workspace-content'));
      expect(tester.getTopLeft(content).dy, 24 + 40 + 48);
      final list = tester.widget<ListView>(
        find.descendant(of: content, matching: find.byType(ListView)).first,
      );
      expect(list.padding, const EdgeInsets.fromLTRB(20, 8, 20, 30));
      expect(
        tester
                .getTopLeft(
                  find
                      .descendant(
                        of: content,
                        matching: find.text('Claude Code'),
                      )
                      .first,
                )
                .dy -
            tester.getTopLeft(content).dy,
        lessThan(20),
      );
      expect(
        tester.getSize(find.byTooltip('返回会话首页')).height,
        greaterThanOrEqualTo(48),
      );
      expect(find.byTooltip('刷新会话'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
