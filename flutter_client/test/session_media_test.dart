import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/session_web.dart';
import 'package:g_collie_flutter/session_video.dart';

void main() {
  test(
    'session webpages stay on http and https and reject credentials and native intents',
    () {
      expect(sessionWebUrl(Uri.parse('https://example.com/guide')), true);
      for (final raw in [
        'file:///etc/passwd',
        'intent://example',
        'https://user:secret@example.com',
        'javascript:alert(1)',
      ]) {
        expect(sessionWebUrl(Uri.parse(raw)), false);
      }
    },
  );
  test(
    'video references handle signed query strings and do not classify images',
    () {
      expect(isSessionVideo('/media/clip.MP4?token=test'), true);
      expect(isSessionVideo('https://example.com/clip.webm#play'), true);
      expect(isSessionVideo('/media/photo.jpg'), false);
    },
  );
  test(
    'video cards preserve spaced paths, original uploads and MEDIA references',
    () {
      expect(
        sessionVideoReferences(
          '[视频](</home/user/My Folder/a.mp4>)\n[clip.mp4](/uploads/id/content)\nMEDIA: /tmp/other.webm',
        ),
        {
          '/home/user/My Folder/a.mp4',
          '/uploads/id/content',
          '/tmp/other.webm',
        },
      );
      expect(sessionVideoReferences('![clip](/tmp/a.mp4)'), isEmpty);
    },
  );
}
