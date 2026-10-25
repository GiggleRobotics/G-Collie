import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:g_collie_flutter/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';

import 'package:g_collie_flutter/resources.dart';

class DownloadApi extends CollieApi {
  DownloadApi() : super(Uri.parse('http://localhost:4310'));
  @override
  Future<dynamic> call(String path, [Json? body]) async => body == null
      ? {
          'resources': [
            {
              'id': 'file',
              'ref': '/tmp/screen.png',
              'name': 'screen.png',
              'image': true,
            },
          ],
        }
      : {'path': '/preview/${'a' * 48}/view'};
  @override
  Future<Uri> browserPreview(String path) async =>
      Uri.parse('http://127.0.0.1:1234$path');
}

void main() {
  testWidgets(
    'download link enqueues original file without opening a preview route',
    (tester) async {
      final api = DownloadApi();
      addTearDown(api.close);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeBridge.channel,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeBridge.channel,
          null,
        ),
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await SessionResources(
        api,
        'codex:test',
      ).download(context, '/tmp/screen.png');
      expect(calls.single.method, 'downloadFile');
      expect(
        calls.single.arguments['url'],
        'http://127.0.0.1:1234/preview/${'a' * 48}/content?download=1',
      );
      expect(calls.single.arguments['name'], 'screen.png');
      expect(find.text('图片查看'), findsNothing);
    },
  );
}
