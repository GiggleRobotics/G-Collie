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
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==',
    );
  }
}

void main() {
  for (final source in [
    '/portrait.png',
    'https://example.invalid/portrait.png',
  ]) {
    testWidgets('portrait image paints at requested left alignment: $source', (
      tester,
    ) async {
      final api = CollieApi(Uri.parse('http://localhost'));
      final images = RetryImages(api)..calls = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 480,
              child: SessionImage(
                resources: images,
                source: source,
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final image = find.byType(Image);
      expect(image, findsOneWidget);
      expect(tester.widget<Image>(image).alignment, Alignment.centerLeft);
      expect(tester.widget<Image>(image).fit, BoxFit.contain);
      await tester.pumpWidget(const SizedBox());
      api.close();
    });
  }

  for (final valid in [true, false]) {
    testWidgets(
      'image codec emits a content-free ${valid ? 'success' : 'failure'} diagnostic',
      (tester) async {
        final messages = <String>[];
        final previous = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) messages.add(message);
        };
        final api = CollieApi(Uri.parse('http://localhost'));
        final images = DiagnosticImages(api, valid);
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SessionImage(
                  resources: images,
                  source: '/private-image-name.png',
                ),
              ),
            ),
          );
          // Codec work runs outside the fake frame clock. Wait for the actual
          // image frame/error callback instead of treating an idle scheduler as
          // proof that decoding completed.
          final expected =
              'GCollieImage codec ${valid ? 'success' : 'failure'}';
          for (var attempt = 0;
              attempt < 100 && !messages.contains(expected);
              attempt++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          expect(
            messages,
            contains('GCollieImage codec ${valid ? 'success' : 'failure'}'),
          );
          expect(
            messages
                .where((line) => line.startsWith('GCollieImage'))
                .any((line) => line.contains('private-image-name')),
            isFalse,
          );
          if (!valid) expect(find.textContaining('点击打开或重试'), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox());
          api.close();
          debugPrint = previous;
        }
      },
    );
  }

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
    expect(
      tester.widget<Image>(find.byType(Image)).alignment,
      Alignment.center,
    );
    expect(find.textContaining('点击打开或重试'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}

class DiagnosticImages extends RetryImages {
  final bool valid;
  DiagnosticImages(super.api, this.valid);
  @override
  Future<Uint8List> image(String ref) async {
    if (!valid) return Uint8List.fromList([0, 1, 2, 3]);
    calls = 1;
    return super.image(ref);
  }
}
