import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/main.dart';
import 'package:g_collie_flutter/resources.dart';
import 'package:g_collie_flutter/session_gallery.dart';
import 'package:g_collie_flutter/ui.dart';

import 'workspace_test.dart' show FakeApi;

const first = 'https://images.invalid/render?id=1';
const second = 'https://images.invalid/render?id=2';
const otherLink = 'https://docs.invalid/about';

class _RemoteHistory extends FakeApi {
  @override
  Future<dynamic> call(String path, [Json? body]) async {
    if (path.endsWith('/resources')) return {'resources': []};
    final value = await super.call(path, body);
    if (path == '/local/codex%3Aone') {
      value['events'] = [
        {
          'id': 'old',
          'role': 'assistant',
          'phase': 'commentary',
          'text': '[说明]($otherLink)',
          'media': [first, second],
        },
      ];
    }
    return value;
  }
}

void main() {
  testWidgets(
    'structured URL-only images open together from a commentary gallery',
    (tester) async {
      final api = _RemoteHistory();
      addTearDown(api.close);
      // Seed the two public image providers. Session resources only list local files.
      for (final ref in [first, second]) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const Color(0xffaa6622), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final info = ImageInfo(image: picture.toImageSync(80, 40));
        picture.dispose();
        final provider = NetworkImage(ref);
        PaintingBinding.instance.imageCache.putIfAbsent(
          provider,
          () => OneFrameImageStreamCompleter(Future.value(info)),
        );
        addTearDown(() => provider.evict());
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(api: api, role: 'view'),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<CollieShell>(find.byType(CollieShell)).onOpen('codex:one');
      await tester.pumpAndSettle();

      final thumbnails = find.descendant(
        of: find.byType(SessionGallery),
        matching: find.byType(Image),
      );
      expect(
        tester.widgetList<Image>(thumbnails).map((w) => w.image),
        containsAll([const NetworkImage(first), const NetworkImage(second)]),
      );
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      await tester.tap(find.byType(SessionImage));
      await tester.pumpAndSettle();
      final gallery = tester.widget<SessionMediaBrowser>(
        find.byType(SessionMediaBrowser),
      );
      expect(gallery.items.map((item) => item['ref']), [first, second]);
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('下一个媒体'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('gallery-image:$second')),
        findsOneWidget,
      );
    },
  );
}
