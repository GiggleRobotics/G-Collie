import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';

class ComputerStore {
  final FlutterSecureStorage storage;
  ComputerStore(this.storage);
  static Future<void> _writes = Future.value();
  Future<void> _write(Future<void> Function() operation) {
    final pending = _writes.then((_) => operation());
    _writes = pending.catchError((_) {});
    return pending;
  }

  Future<List<Json>> read() async {
    final raw = await storage.read(key: 'paired-computers-v1');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
  }

  Future<void> remember(
    Uri base,
    String role, {
    String? name,
    bool select = true,
  }) => _write(() async {
    final rows = await read();
    final existing = rows.where((c) => c['address'] == '$base').firstOrNull;
    if (existing != null) {
      existing['role'] = role;
      if (name != null && name.trim().isNotEmpty) existing['name'] = name;
    } else {
      rows.add({'address': '$base', 'name': name ?? base.host, 'role': role});
    }
    await storage.write(key: 'paired-computers-v1', value: jsonEncode(rows));
    if (select) await storage.write(key: 'server', value: '$base');
  });

  Future<void> forget(Uri base) => _write(() async {
    final rows = await read();
    rows.removeWhere((c) => c['address'] == '$base');
    await storage.write(key: 'paired-computers-v1', value: jsonEncode(rows));
    await storage.delete(key: 'cookie:$base');
    await storage.delete(key: 'workspace-cache:$base');
    if (await storage.read(key: 'server') == '$base') {
      if (rows.isEmpty) {
        await storage.delete(key: 'server');
      } else {
        await storage.write(key: 'server', value: rows.first['address']);
      }
    }
  });
}
