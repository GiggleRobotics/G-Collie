import 'api.dart';
import 'diagnostic_log.dart';

class DiagnosticSync {
  final CollieApi api;
  DateTime last = DateTime.fromMillisecondsSinceEpoch(0);
  bool busy = false;
  DiagnosticSync(this.api);
  Future<void> tick() async {
    if (busy || DateTime.now().difference(last).inSeconds < 30) return;
    busy = true;
    last = DateTime.now();
    try {
      final data = await api.call('/diagnostics/requests/pending');
      for (final r in data['requests'] as List? ?? []) {
        await upload(
          DateTime.fromMillisecondsSinceEpoch(r['from']),
          DateTime.fromMillisecondsSinceEpoch(r['to']),
          requestId: r['id'],
        );
      }
    } catch (_) {
      /* Explicit remote requests remain queued until the phone can reply. */
    } finally {
      busy = false;
    }
  }

  Future<void> upload(DateTime from, DateTime to, {String? requestId}) async {
    final rows = await DiagnosticLog.between(api.base.host, from, to);
    await api.call('/diagnostics/phone', {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
      'events': rows,
      if (requestId != null) 'requestId': requestId,
    });
  }
}
