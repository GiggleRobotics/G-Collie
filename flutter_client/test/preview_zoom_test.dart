import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/preview.dart';

void main() {
  testWidgets(
    'wide image uses full viewport and double tap zoom works immediately',
    (tester) async {
      final data = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 1200, 300),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(1200, 300);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        return bytes;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: FilePreviewPage(
            name: 'wide.png',
            url: Uri.parse('http://localhost/preview/test/view'),
            image: Future.value(data),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      final viewer = find.byType(InteractiveViewer);
      expect(viewer, findsOneWidget);
      final size = tester.getSize(viewer);
      expect(
        size.width,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      );
      expect(size.height, greaterThan(400));
      final widget = tester.widget<InteractiveViewer>(viewer);
      expect(tester.getSize(find.byType(Image)), size);
      // Double tap in the blank area below a wide image must also zoom.
      final point =
          tester.getTopLeft(viewer) + Offset(size.width / 2, size.height - 30);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(widget.transformationController!.value.getMaxScaleOnAxis(), 3);
      expect(tester.getSize(viewer), size);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(widget.transformationController!.value.getMaxScaleOnAxis(), 1);
    },
  );
}
