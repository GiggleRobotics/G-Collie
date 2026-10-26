import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/offline_assets.dart';

void main() {
  test(
    'cached images survive a new read and remain isolated by computer and session',
    () async {
      final dir = await Directory.systemTemp.createTemp('collie-images-');
      OfflineAssets.directoryOverride = dir;
      try {
        final key = OfflineAssets.key('computer-a', 'session-a', 'image.png');
        await OfflineAssets.save(key, Uint8List.fromList([1, 2, 3]));
        expect(await OfflineAssets.read(key), [1, 2, 3]);
        expect(
          await OfflineAssets.read(
            OfflineAssets.key('computer-b', 'session-a', 'image.png'),
          ),
          isNull,
        );
        expect(
          await OfflineAssets.read(
            OfflineAssets.key('computer-a', 'session-b', 'image.png'),
          ),
          isNull,
        );
        await OfflineAssets.clear();
        expect(await OfflineAssets.read(key), isNull);
      } finally {
        OfflineAssets.directoryOverride = null;
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    },
  );
}
