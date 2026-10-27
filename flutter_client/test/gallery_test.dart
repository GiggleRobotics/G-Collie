import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/resources.dart';

class GalleryResources extends SessionResources {
  String? opened;
  GalleryResources(CollieApi api) : super(api, 'codex:test');
  @override
  Future<Uint8List> image(String ref) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7ZkAAAAASUVORK5CYII=',
  );
  @override
  Future<void> open(BuildContext context, String ref) async {
    opened = ref;
  }
}

void main() {
  testWidgets(
    'gallery has one large image, clickable thumbnails, persistent selection and correct preview',
    (tester) async {
      final api = CollieApi(Uri.parse('http://localhost'));
      final resources = GalleryResources(api);
      Widget page(List<String> refs) => MaterialApp(
        home: Scaffold(
          body: SessionGallery(resources: resources, sources: refs),
        ),
      );
      await tester.pumpWidget(page(['a', 'b', 'c']));
      await tester.pumpAndSettle();
      expect(find.byType(SessionImage), findsOneWidget);
      expect(
        tester.widget<SessionImage>(find.byType(SessionImage)).source,
        'a',
      );
      final third = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '选择第 3 张图片',
      );
      await tester.tap(third);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SessionImage>(find.byType(SessionImage)).source,
        'c',
      );
      await tester.pumpWidget(page(['a', 'b', 'c']));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SessionImage>(find.byType(SessionImage)).source,
        'c',
      );
      await tester.tap(find.byType(SessionImage));
      expect(resources.opened, 'c');
      await tester.pumpWidget(page(['a', 'b']));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SessionImage>(find.byType(SessionImage)).source,
        'a',
      );
      expect(tester.takeException(), isNull);
      api.close();
    },
  );
}
