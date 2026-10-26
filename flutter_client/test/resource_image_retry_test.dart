import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/resources.dart';

class RetryImages extends SessionResources {
  int calls = 0;
  RetryImages(CollieApi api) : super(api, 'codex:test');
  @override
  Future<Uint8List> image(String ref) async {
    if (++calls == 1) throw ApiException('临时读取失败');
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7ZkAAAAASUVORK5CYII=',
    );
  }
}

void main() {
  testWidgets('thumbnail retries a transient failure without requiring a tap', (
    tester,
  ) async {
    final api = CollieApi(Uri.parse('http://localhost'));
    final images = RetryImages(api);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionImage(resources: images, source: '/photo.png'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(images.calls, 2);
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('点击打开或重试'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
