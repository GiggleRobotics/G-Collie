import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DiagnosticLog {
  static const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static Future<void> writes = Future.value();
  static final samples = <String, DateTime>{};
  static String route(String path) =>
      path.split('?').first.replaceAll(RegExp(r'[a-f0-9-]{16,}'), ':id');
  static Future<void> record(
    String computer,
    String path,
    String category, {
    String? requestId,
    int? durationMs,
    int? status,
    bool sample = false,
  }) {
    final key = '$computer:${route(path)}:$category',
        now = DateTime.now().toUtc();
    if (sample &&
        samples[key] != null &&
        now.difference(samples[key]!).inSeconds < 60) {
      return Future.value();
    }
    samples[key] = now;
    if (samples.length > 200) samples.remove(samples.keys.first);
    final pending = writes.catchError((_) {}).then((_) async {
      final rows = await read();
      rows.add({
        'time': now.toIso8601String(),
        'computer': computer,
        'route': route(path),
        'category': category,
        if (requestId != null) 'requestId': requestId,
        if (durationMs != null) 'durationMs': durationMs,
        if (status != null) 'status': status,
      });
      final cutoff = now.subtract(const Duration(days: 7));
      rows.removeWhere(
        (e) => DateTime.tryParse('${e['time']}')?.isBefore(cutoff) ?? true,
      );
      while (rows.length > 1000 ||
          utf8.encode(jsonEncode(rows)).length > 400 * 1024) {
        rows.removeAt(0);
      }
      await storage.write(key: 'diagnostic-events-v2', value: jsonEncode(rows));
    });
    writes = pending;
    return pending;
  }

  static Future<List<Map<String, dynamic>>> read() async {
    final raw = await storage.read(key: 'diagnostic-events-v2');
    final rows = raw == null ? [] : jsonDecode(raw) as List;
    return rows
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> between(
    String computer,
    DateTime from,
    DateTime to,
  ) async {
    await writes.catchError((_) {});
    final rows = await read();
    return rows.where((e) {
      final t = DateTime.tryParse('${e['time']}');
      return e['computer'] == computer &&
          t != null &&
          !t.isBefore(from) &&
          !t.isAfter(to);
    }).toList();
  }
}
