import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'native.dart';

class OfflineAssets {
  static Directory? directoryOverride;
  static Future<void> writes = Future.value();
  static Future<Directory?> directory() async {
    if (directoryOverride != null) return directoryOverride;
    try {
      final path = await NativeBridge.invoke<String>('offlineDirectory');
      return path == null ? null : Directory(path);
    } catch (_) {
      return null;
    }
  }

  static String key(String computer, String session, String ref) =>
      jsonEncode([computer, session, ref]);
  static String name(String key) {
    var hash = 0x811c9dc5;
    for (final b in utf8.encode(key)) {
      hash = ((hash ^ b) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }

  static Future<Uint8List?> read(String key) async {
    await writes.catchError((_) {});
    final dir = await directory();
    if (dir == null) return null;
    try {
      final meta = jsonDecode(
        await File('${dir.path}/${name(key)}.json').readAsString(),
      );
      if (meta['key'] != key) return null;
      return await File('${dir.path}/${name(key)}.bin').readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String key, List<int> bytes) {
    if (bytes.length > 8 * 1024 * 1024) return Future.value();
    final pending = writes.catchError((_) {}).then((_) async {
      final dir = await directory();
      if (dir == null) return;
      await dir.create(recursive: true);
      final root = '${dir.path}/${name(key)}';
      await File('$root.bin').writeAsBytes(bytes, flush: true);
      await File('$root.json').writeAsString(jsonEncode({'key': key}));
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.bin'))
          .cast<File>()
          .toList();
      final entries = <MapEntry<File, FileStat>>[];
      for (final f in files) {
        entries.add(MapEntry(f, await f.stat()));
      }
      entries.sort((a, b) => a.value.modified.compareTo(b.value.modified));
      var size = entries.fold<int>(0, (sum, e) => sum + e.value.size);
      for (final e in entries) {
        if (size <= 50 * 1024 * 1024) break;
        size -= e.value.size;
        await e.key.delete();
        final meta = File(e.key.path.replaceFirst(RegExp(r'\.bin$'), '.json'));
        if (await meta.exists()) await meta.delete();
      }
    });
    writes = pending;
    return pending;
  }

  static Future<void> clear({String? computer}) async {
    await writes.catchError((_) {});
    final dir = await directory();
    if (dir == null || !await dir.exists()) return;
    if (computer == null) {
      await dir.delete(recursive: true);
      return;
    }
    await for (final file in dir.list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      try {
        final meta = jsonDecode(await file.readAsString());
        if ((jsonDecode(meta['key']) as List).first != computer) continue;
        final bytes = File(file.path.replaceFirst(RegExp(r'\.json$'), '.bin'));
        if (await bytes.exists()) await bytes.delete();
        await file.delete();
      } catch (_) {}
    }
  }
}
