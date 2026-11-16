import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/codex_capabilities.dart';

class CapabilityApi extends CollieApi {
  final writes = <String>[];
  String mode = 'default';
  CapabilityApi() : super(Uri.parse('http://preview.invalid'));
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (body != null) {
      writes.add(path);
      if (path.endsWith('/mode')) mode = body['mode'];
      return {};
    }
    return {
      'mode': mode,
      'modes': {
        'data': {
          'data': [
            {'mode': 'plan'},
            {'mode': 'default'},
          ],
        },
      },
      'goal': {
        'data': {'goal': null},
      },
      'plugins': {
        'data': {'marketplaces': []},
      },
      'skills': [],
    };
  }
}

class DelayedCapabilityApi extends CapabilityApi {
  final result = Completer<dynamic>();
  @override
  Future<dynamic> call(String path, [Json? body]) => result.future;
}

void main() {
  testWidgets('goal cannot be edited before loaded or on a read-only device', (
    tester,
  ) async {
    final api = DelayedCapabilityApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CodexCapabilities(
          api: api,
          session: 'codex:target',
          enabled: true,
        ),
      ),
    );
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    api.result.complete({
      'goal': {
        'data': {
          'goal': {'objective': '已保存目标'},
        },
      },
      'skills': [],
    });
    await tester.pumpAndSettle();
    expect(find.text('已保存目标'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, true);
    await tester.pumpWidget(
      MaterialApp(
        home: CodexCapabilities(
          api: api,
          session: 'codex:target',
          enabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mode and goal use native API, disabled device cannot mutate', (
    tester,
  ) async {
    final api = CapabilityApi();
    await tester.pumpWidget(
      MaterialApp(
        home: CodexCapabilities(
          api: api,
          session: 'codex:target',
          enabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('计划模式').last);
    await tester.pumpAndSettle();
    expect(api.writes, ['/local/codex%3Atarget/mode']);
    await tester.enterText(find.byType(TextField), '整理待办');
    await tester.pump();
    await tester.ensureVisible(find.text('保存目标'));
    await tester.tap(find.text('保存目标'));
    await tester.pumpAndSettle();
    expect(api.writes.last, '/local/codex%3Atarget/goal');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: CodexCapabilities(
          api: api,
          session: 'codex:target',
          enabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final count = api.writes.length;
    await tester.tap(find.text('计划模式').last);
    await tester.pumpAndSettle();
    expect(api.writes.length, count);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
