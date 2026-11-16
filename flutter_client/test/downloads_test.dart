import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/downloads.dart';
import 'package:g_collie_flutter/native.dart';

void main() {
  testWidgets(
    'downloads distinguish pending, failed and recovered empty records',
    (tester) async {
      final pending = Completer<List<dynamic>>();
      bool recover = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeBridge.channel,
        (call) async {
          if (call.method != 'downloads') return null;
          return recover ? [] : pending.future;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeBridge.channel,
          null,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: DownloadsPage()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('还没有下载内容'), findsNothing);
      pending.completeError(
        PlatformException(code: 'downloads', message: '测试读取失败'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('下载记录加载失败'), findsOneWidget);
      expect(find.text('还没有下载内容'), findsNothing);
      recover = true;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.textContaining('测试读取失败'), findsNothing);
      expect(find.text('还没有下载内容'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'downloads show actual system states and filter completed files',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeBridge.channel,
        (call) async => call.method == 'downloads'
            ? [
                {'id': 1, 'name': 'done.png', 'status': 8},
                {'id': 2, 'name': 'failed.pdf', 'status': 16, 'reason': 1006},
              ]
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeBridge.channel,
          null,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: DownloadsPage()));
      await tester.pumpAndSettle();
      expect(find.text('done.png'), findsOneWidget);
      expect(find.text('failed.pdf'), findsOneWidget);
      await tester.tap(find.text('已完成'));
      await tester.pumpAndSettle();
      expect(find.text('failed.pdf'), findsNothing);
      expect(find.text('打开'), findsOneWidget);
      await tester.tap(find.text('下载中'));
      await tester.pumpAndSettle();
      expect(find.text('暂无下载中的下载内容'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
