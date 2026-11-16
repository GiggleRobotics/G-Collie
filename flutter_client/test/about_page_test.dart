import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/ui.dart';
import 'workspace_test.dart' show FakeApi;
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/about_page.dart';
import 'package:g_collie_flutter/native.dart';

void main() {
  testWidgets(
    'workspace child sheets replace the parent and restore it when closed',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = FakeApi();
      final computersClosed = Completer<void>();
      var computersOpened = false;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(
            api: api,
            role: 'view',
            onManageComputers: () async {
              computersOpened = true;
              await computersClosed.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic shell = tester.state(find.byType(CollieShell));
      final Future<void> menu = shell.workspaceMenu();
      await tester.pumpAndSettle();
      await tester.tap(find.text('关于 G-Collie'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutContent), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.byTooltip('关闭关于 G-Collie'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutContent), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      for (final title in ['通知', '外观']) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('关于 G-Collie'), findsNothing);
        await tester.tap(find.byTooltip('关闭$title'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('关于 G-Collie'), findsOneWidget);
      }
      await tester.tap(find.text('电脑与连接'));
      await tester.pumpAndSettle();
      expect(computersOpened, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
      computersClosed.complete();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      Navigator.of(tester.element(find.text('关于 G-Collie'))).pop();
      await tester.pumpAndSettle();
      await menu;
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(CollieShell), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(390, 844), const Size(890, 400)]) {
    for (final scale in [1.3, 1.6]) {
      testWidgets(
        'about keeps centered concise sheet content at $size / $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            NativeBridge.channel,
            (_) async => '0.1.38',
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(NativeBridge.channel, null),
          );
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const Scaffold(
                body: SingleChildScrollView(child: AboutContent()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('内测版 0.1.38 · By Giggle'), findsOneWidget);
          expect(find.byType(SingleChildScrollView), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          expect(
            find.text('本版更新：Codex / Hermes / Claude Code 会话、项目用量、照片与文件、工作台设置。'),
            findsOneWidget,
          );
          expect(
            tester.widget<Text>(find.text('G-Collie')).textAlign,
            TextAlign.center,
          );
          await tester.scrollUntilVisible(
            find.text('反馈时请提供页面提示、Agent 类型及会话 ID，方便定位问题。'),
            180,
            scrollable: find.byType(Scrollable).last,
          );
          expect(
            find.text('反馈时请提供页面提示、Agent 类型及会话 ID，方便定位问题。').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
