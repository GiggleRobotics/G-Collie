import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/native.dart';
import 'package:g_collie_flutter/ui.dart';
import 'workspace_test.dart' show FakeApi;

class AttachmentApi extends FakeApi {
  int uploads = 0;
  Completer<dynamic>? uploadResult;
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path == '/attachments') {
      uploads++;
      return uploadResult?.future ?? {'id': 'photo', 'name': 'photo.png'};
    }
    final result = await super.call(path, body);
    if (path == '/local/codex%3Atwo') result['id'] = 'codex:two';
    return result;
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final unmount in [false, true]) {
    testWidgets(
      'late native selection ignored after ${unmount ? 'unmount' : 'session switch'}',
      (tester) async {
        final api = AttachmentApi();
        final selected = Completer<String?>();
        late Directory directory;
        late File file;
        await tester.runAsync(() async {
          directory = await Directory.systemTemp.createTemp('gcollie-picker-');
          file = await File('${directory.path}/picked.png').writeAsBytes([1]);
        });
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeBridge.channel,
          (call) async =>
              call.method == 'clipboardImage' ? selected.future : null,
        );
        addTearDown(() async {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            NativeBridge.channel,
            null,
          );
          await directory.delete(recursive: true);
          api.close();
        });
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
        final dynamic state = tester.state(find.byType(CollieShell));
        late Future<void> selecting;
        await tester.runAsync(() async {
          selecting = state.upload('clipboard');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        if (unmount) {
          await tester.pumpWidget(const SizedBox());
        } else {
          tester
              .widget<CollieShell>(find.byType(CollieShell))
              .onOpen('codex:two');
          await tester.pump(const Duration(milliseconds: 200));
        }
        selected.complete(file.path);
        await tester.runAsync(() => selecting);
        await tester.pump();
        expect(api.uploads, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final returnDuringUpload in [false, true]) {
    testWidgets(
      'picker result survives resume loading during ${returnDuringUpload ? 'upload response' : 'native selection'}',
      (tester) async {
        final api = AttachmentApi();
        final selected = Completer<String?>();
        if (returnDuringUpload) api.uploadResult = Completer<dynamic>();
        late Directory directory;
        late File file;
        await tester.runAsync(() async {
          directory = await Directory.systemTemp.createTemp('gcollie-resume-');
          file = await File('${directory.path}/picked.png').writeAsBytes([1]);
        });
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeBridge.channel,
          (call) async =>
              call.method == 'clipboardImage' ? selected.future : null,
        );
        addTearDown(() async {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            NativeBridge.channel,
            null,
          );
          await directory.delete(recursive: true);
          api.close();
        });
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
        final dynamic shellState = tester.state(find.byType(CollieShell));
        final dynamic workspaceState = tester.state(find.byType(Workspace));
        late Future<void> selecting;
        await tester.runAsync(() async {
          selecting = shellState.upload('clipboard');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        if (returnDuringUpload) {
          selected.complete(file.path);
          await tester.runAsync(() async {
            while (api.uploads == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          });
        }
        // A picker resumes the same Workspace while its detail refresh is loading.
        // Composer interaction is disabled, but session permission is unchanged.
        workspaceState.setState(() => workspaceState.loading = true);
        await tester.pump();
        final shell = tester.widget<CollieShell>(find.byType(CollieShell));
        expect(shell.enabled, isFalse);
        expect(shell.attachmentEnabled, isTrue);
        if (returnDuringUpload) {
          api.uploadResult!.complete({'id': 'photo', 'name': 'photo.png'});
        } else {
          selected.complete(file.path);
        }
        await tester.runAsync(() => selecting);
        await tester.pump();
        expect(api.uploads, 1);
        expect(shellState.uploads, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final revoke in [false, true]) {
    testWidgets(
      'picker result ignored after ${revoke ? 'permission revoked' : 'offline'}',
      (tester) async {
        final api = AttachmentApi();
        final selected = Completer<String?>();
        late Directory directory;
        late File file;
        await tester.runAsync(() async {
          directory = await Directory.systemTemp.createTemp(
            'gcollie-permission-',
          );
          file = await File('${directory.path}/picked.png').writeAsBytes([1]);
        });
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeBridge.channel,
          (call) async =>
              call.method == 'clipboardImage' ? selected.future : null,
        );
        addTearDown(() async {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            NativeBridge.channel,
            null,
          );
          await directory.delete(recursive: true);
          api.close();
        });
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
        final dynamic shellState = tester.state(find.byType(CollieShell));
        final dynamic workspaceState = tester.state(find.byType(Workspace));
        late Future<void> selecting;
        await tester.runAsync(() async {
          selecting = shellState.upload('clipboard');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        workspaceState.setState(() {
          if (revoke) {
            workspaceState.effectiveRole = 'view';
          } else {
            workspaceState.online = false;
          }
        });
        await tester.pump();
        expect(
          tester
              .widget<CollieShell>(find.byType(CollieShell))
              .attachmentEnabled,
          isFalse,
        );
        selected.complete(file.path);
        await tester.runAsync(() => selecting);
        await tester.pump();
        expect(api.uploads, 0);
        expect(shellState.uploads, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('old upload failure cannot become new session error', (
    tester,
  ) async {
    final api = AttachmentApi()..uploadResult = Completer<dynamic>();
    late Directory directory;
    late File file;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('gcollie-upload-');
      file = await File('${directory.path}/picked.png').writeAsBytes([1]);
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeBridge.channel,
      (call) async => call.method == 'clipboardImage' ? file.path : null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeBridge.channel,
        null,
      );
      await directory.delete(recursive: true);
      api.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(api: api, role: 'control', initialSession: 'codex:one'),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(CollieShell));
    late Future<void> uploading;
    await tester.runAsync(() async {
      uploading = state.upload('clipboard');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.runAsync(() async {
      while (api.uploads == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    tester.widget<CollieShell>(find.byType(CollieShell)).onOpen('codex:two');
    await tester.pump(const Duration(milliseconds: 200));
    api.uploadResult!.completeError(ApiException('原会话上传失败'));
    await tester.runAsync(() => uploading);
    await tester.pump();
    expect(find.textContaining('原会话上传失败'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
