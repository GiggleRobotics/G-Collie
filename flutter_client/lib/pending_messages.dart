import 'api.dart';

/// Local display receipts are distinct from execution and never trigger a send.
class PendingMessages {
  final Map<String, List<Json>> sessions = {};
  final Map<String, Set<String>> matched = {};
  void add(
    String session,
    String id,
    String text,
    List<dynamic> baseline, {
    bool attachments = false,
  }) {
    final rows = sessions.putIfAbsent(session, () => []);
    if (rows.any((e) => e['id'] == id)) return;
    rows.removeWhere(
      (e) =>
          e['sendStatus'] == 'failed' &&
          e['text'] == (text.isEmpty && attachments ? '附件消息' : text) &&
          e['attachments'] == attachments,
    );
    rows.add({
      'id': id,
      'role': 'user',
      'text': text.isEmpty && attachments ? '附件消息' : text,
      'time': DateTime.now().millisecondsSinceEpoch,
      'sendStatus': 'sending',
      'attachments': attachments,
      'baseline': baseline.map((e) => e['id']).toList(),
    });
  }

  void update(String session, String id, String status, {String? turnId}) {
    for (final row in sessions[session] ?? <Json>[]) {
      if (row['id'] == id) {
        row['sendStatus'] = status;
        if (turnId != null) row['turnId'] = turnId;
      }
    }
  }

  void move(String from, String to) {
    final rows = sessions.remove(from);
    if (rows != null) sessions.putIfAbsent(to, () => []).addAll(rows);
  }

  Json merge(Json detail) {
    final session = detail['id'] as String;
    final events = List<dynamic>.from(detail['events'] ?? []);
    final rows = sessions[session] ?? <Json>[];
    final claimed = matched.putIfAbsent(session, () => <String>{});
    rows.removeWhere((row) {
      final baseline = Set<dynamic>.from(row['baseline'] ?? []);
      final match = events
          .where(
            (e) =>
                e['role'] == 'user' &&
                e['sendStatus'] == null &&
                !baseline.contains(e['id']) &&
                !claimed.contains('${e['id']}') &&
                (row['turnId'] != null ||
                    (e['time'] ?? 0) >= row['time'] - 2000) &&
                (row['turnId'] == null || e['turnId'] == row['turnId']) &&
                ('${e['text']}'.trim() == '${row['text']}'.trim() ||
                    (row['attachments'] == true &&
                        row['turnId'] != null &&
                        ('${row['text']}' == '附件消息' ||
                            '${e['text']}'.startsWith('${row['text']}')))),
          )
          .firstOrNull;
      if (match == null) return false;
      claimed.add('${match['id']}');
      if (claimed.length > 1000) claimed.remove(claimed.first);
      return true;
    });
    // Pending records remain visible across stale history responses.
    return {
      ...detail,
      'events': [...events.where((e) => e['sendStatus'] == null), ...rows],
    };
  }
}
