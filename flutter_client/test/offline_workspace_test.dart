import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/api.dart';

class OfflineApi extends CollieApi {
  final calls = <String>[];
  OfflineApi() : super(Uri.parse('http://offline.example:4310'));
  @override
  Future<dynamic> call(String p, [Json? b]) async {
    calls.add(p);
    throw Exception('offline');
  }
}

void main() {
  testWidgets(
    'offline history and per-session draft reopen without waiting for a detail request',
    (tester) async {
      final api = OfflineApi();
      FlutterSecureStorage.setMockInitialValues({
        'workspace-cache:${api.base}': jsonEncode({
          'sessions': [
            {'id': 'codex:cached', 'title': 'Cached chat', 'agent': 'Codex'},
          ],
          'projects': [],
          'details': {
            'codex:cached': {
              'id': 'codex:cached',
              'title': 'Cached chat',
              'agent': 'Codex',
              'events': [
                {'role': 'assistant', 'text': 'Saved answer'},
              ],
              'pending': {'id': 'old', 'kind': 'approval'},
            },
          },
        }),
        'workspace-drafts:${api.base}': jsonEncode({
          'codex:cached': 'unsent draft',
        }),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'control'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cached chat'));
      await tester.pumpAndSettle();
      expect(find.text('Saved answer'), findsOneWidget);
      expect(find.text('unsent draft'), findsOneWidget);
      expect(api.calls.where((p) => p.startsWith('/local/')), isEmpty);
      expect(find.text('批准一次'), findsNothing);
      await tester.enterText(
        find.byType(TextField).last,
        'updated offline draft',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final saved = await const FlutterSecureStorage().read(
        key: 'workspace-drafts:${api.base}',
      );
      expect(jsonDecode(saved!)['codex:cached'], 'updated offline draft');
      api.close();
    },
  );
}
