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

void main() {
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
