import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/ui.dart';
import 'package:g_collie_flutter/computers.dart';
import 'package:g_collie_flutter/native.dart';

void main() {
  for (final first in [true, false]) {
    testWidgets(
      '${first ? 'first pairing' : 'add computer'} accepts link in either field without submitting',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeBridge.channel,
          (call) async => null,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: first
                  ? const ConnectionPage()
                  : AddComputerPane(
                      computers: ComputerStore(const FlutterSecureStorage()),
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        expect(fields, findsAtLeastNWidgets(2));
        await tester.enterText(fields.at(0), 'http://qa:4310/#pair=123456');
        await tester.pump();
        expect(
          tester.widget<TextField>(fields.at(0)).controller!.text,
          'http://qa:4310/',
        );
        expect(
          tester.widget<TextField>(fields.at(1)).controller!.text,
          '123456',
        );
        await tester.enterText(fields.at(1), 'http://next:4310/#pair=654321');
        await tester.pump();
        expect(
          tester.widget<TextField>(fields.at(0)).controller!.text,
          'http://next:4310/',
        );
        expect(
          tester.widget<TextField>(fields.at(1)).controller!.text,
          '654321',
        );
        for (final invalid in [
          'ftp://qa/#pair=123456',
          'http://user:pass@qa/#pair=123456',
          'http://qa/path#pair=123456',
          'http://qa/#pair=abc',
          'http://qa/#missing=123456',
        ]) {
          for (final field in [0, 1]) {
            await tester.enterText(fields.at(field), invalid);
            await tester.pump();
            expect(
              tester.widget<TextField>(fields.at(0)).controller!.text,
              'http://next:4310/',
            );
            expect(
              tester.widget<TextField>(fields.at(1)).controller!.text,
              '654321',
            );
          }
        }
        final token = base64Url.encode(
          List<int>.generate(24, (i) => (252 + i * 71) % 256),
        );
        final submit = find.widgetWithText(FilledButton, '配对并连接');
        for (final field in [0, 1]) {
          await tester.enterText(
            fields.at(field),
            'https://qa:4310/#pair=$token',
          );
          await tester.pump();
          expect(
            tester.widget<TextField>(fields.at(0)).controller!.text,
            'https://qa:4310/',
          );
          expect(
            tester.widget<TextField>(fields.at(1)).controller!.text,
            isEmpty,
          );
          expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
          expect(find.textContaining(token), findsNothing);
          expect(
            await const FlutterSecureStorage().read(key: 'server'),
            isNull,
          );
        }
        await tester.enterText(fields.at(0), 'https://other:4310/');
        await tester.pump();
        expect(tester.widget<FilledButton>(submit).onPressed, isNull);
        await tester.enterText(fields.at(1), '');
        await tester.pump();
        expect(tester.widget<TextField>(fields.at(1)).controller!.text, '');
        await tester.enterText(fields.at(1), '123456');
        await tester.pump();
        expect(
          tester.widget<TextField>(fields.at(1)).controller!.text,
          '123456',
        );
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        expect(find.text('正在配对…'), findsNothing);
        expect(find.byType(Workspace), findsNothing);
        expect(await const FlutterSecureStorage().read(key: 'server'), isNull);
        await tester.pumpWidget(const SizedBox());
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeBridge.channel,
          null,
        );
      },
    );
  }
}
