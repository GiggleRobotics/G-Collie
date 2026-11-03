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
    'iVBORw0KGgoAAAANSUhEUgAAAMgAAAEsCAIAAAAJmGvpAAADDklEQVR4nO3SwQ3AIBDAsNLJb3SWIEJC9gR5ZM3MB6f9twN4k7FIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi8QG9sAD2EhV+qEAAAAASUVORK5CYII=',
  );
  @override
  Future<void> gallery(BuildContext context, String ref) async {
    opened = ref;
  }
}

void main() {
  testWidgets(
    'gallery has one large image, clickable thumbnails, persistent selection and correct preview',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = CollieApi(Uri.parse('http://localhost'));
      final resources = GalleryResources(api);
      Widget page(List<String> refs) => MaterialApp(
        home: Scaffold(
          body: SessionGallery(resources: resources, sources: refs),
        ),
      );
      await tester.pumpWidget(page(['a', 'b', 'c']));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SessionImage), findsOneWidget);
      // Main image uses its own ratio, rather than a short landscape frame.
      expect(
        tester.getSize(find.byType(SessionImage)).height,
        greaterThan(300),
      );
      expect(
        tester.widget<SessionImage>(find.byType(SessionImage)).source,
        'a',
      );
      final third = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '选择第 3 张图片',
      );
      await tester.tap(third);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SessionImage>(find.byType(SessionImage)).source,
        'c',
      );
      await tester.pumpWidget(page(['a', 'b', 'c']));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SessionImage>(find.byType(SessionImage)).source,
        'c',
      );
      await tester.tap(find.byType(SessionImage));
      expect(resources.opened, 'c');
      await tester.pumpWidget(page(['a', 'b']));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SessionImage>(find.byType(SessionImage)).source,
        'a',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(page(List.generate(12, (i) => 'image-$i')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      final rail = find.byType(ListView);
      expect(
        tester.getSize(rail).height,
        closeTo(tester.getSize(find.byType(SessionImage)).height, 1),
      );
      await tester.drag(rail, const Offset(0, -550));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '选择第 12 张图片',
        ),
        findsOneWidget,
      );
      api.close();
    },
  );
}
