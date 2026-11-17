import 'api.dart';

/// Local display receipts are distinct from execution and never trigger a send.
class PendingMessages {
  final Map<String, List<Json>> sessions = {};
  final Map<String, Set<String>> matched = {};
  final Map<String, Set<String>> acknowledged = {};
  bool isAcknowledged(String session, String request) =>
      acknowledged[session]?.contains(request) == true;
  void add(
    String session,
    String id,
    String text,
    List<dynamic> baseline, {
    bool attachments = false,
    List<String> attachmentIds = const [],
    List<String> media = const [],
  }) {
    final rows = sessions.putIfAbsent(session, () => []);
    if (rows.any((e) => e['id'] == id)) return;
    rows.removeWhere(
      (e) =>
          e['sendStatus'] == 'failed' &&
          '${e['text'] ?? ''}'.trim() ==
              (text.isEmpty && attachments && media.isEmpty ? '附件消息' : text)
                  .trim() &&
          e['attachments'] == attachments &&
          _sameAttachments(e, attachmentIds, media),
    );
    rows.add({
      'id': id,
      'role': 'user',
      'text': text.isEmpty && attachments && media.isEmpty ? '附件消息' : text,
      'media': media,
      'time': DateTime.now().millisecondsSinceEpoch,
      'sendStatus': 'sending',
      'attachments': attachments,
      'attachmentIds': attachmentIds,
      'baseline': baseline.map((e) => e['id']).toList(),
    });
  }

  bool _sameAttachments(Json row, List<String> ids, List<String> media) {
    bool same(List<dynamic> left, List<dynamic> right) =>
        left.length == right.length &&
        List.generate(left.length, (i) => left[i] == right[i]).every((v) => v);
    final previousIds = row['attachmentIds'] as List? ?? [];
    if (previousIds.isNotEmpty || ids.isNotEmpty) {
      return same(previousIds, ids);
    }
    // Legacy callers without IDs still need the exact preview references.
    return same(row['media'] as List? ?? [], media);
  }

  void update(String session, String id, String status, {String? turnId}) {
    for (final row in sessions[session] ?? <Json>[]) {
      if (row['id'] == id) {
        row['sendStatus'] = status;
        if (turnId != null) row['turnId'] = turnId;
        if (status == 'sent') {
          acknowledged.putIfAbsent(session, () => <String>{}).add(id);
        }
      }
    }
  }

  void move(String from, String to) {
    final rows = sessions.remove(from);
    if (rows != null) sessions.putIfAbsent(to, () => []).addAll(rows);
  }

  bool sameContent(Json row, dynamic event) {
    final text = '${row['text'] ?? ''}'.trim();
    final remote = '${event['text'] ?? ''}'.trim();
    if (row['attachments'] != true) return text == remote;
    final ids = List<String>.from(row['attachmentIds'] ?? []);
    final media = List<String>.from(event['media'] ?? []);
    if (ids.isNotEmpty) {
      return ids.every(
        (id) =>
            (event['attachmentIds'] as List? ?? []).contains(id) ||
            media.any((ref) => ref.contains('/uploads/$id/')) ||
            remote.contains('/uploads/$id/'),
      );
    }
    if (text.isEmpty || text == '附件消息') return media.isNotEmpty;
    return remote == text || remote.startsWith('$text\n');
  }

  Json merge(Json detail) {
    final session = detail['id'] as String;
    final events = List<dynamic>.from(detail['events'] ?? []);
    final rows = sessions[session] ?? <Json>[];
    final claimed = matched.putIfAbsent(session, () => <String>{});
    final receipts = {
      for (final r in detail['sendReceipts'] as List? ?? [])
        if (r is Map && r['requestId'] is String && r['turnId'] is String)
          r['requestId']: r['turnId'],
    };
    rows.removeWhere((row) {
      if (receipts.containsKey(row['id'])) {
        row['turnId'] = receipts[row['id']];
        row['sendStatus'] = 'sent';
        acknowledged.putIfAbsent(session, () => <String>{}).add(row['id']);
      }
      final baseline = Set<dynamic>.from(row['baseline'] ?? []);
      final match = events
          .where(
            (e) =>
                e['role'] == 'user' &&
                e['sendStatus'] == null &&
                !baseline.contains(e['id']) &&
                !claimed.contains('${e['id']}') &&
                (e['requestId'] == row['id'] ||
                    ((row['turnId'] != null ||
                            (e['time'] ?? 0) >= row['time'] - 2000) &&
                        (row['turnId'] == null ||
                            e['turnId'] == row['turnId'] ||
                            (e['turnId'] == null &&
                                (e['time'] ?? 0) >= row['time'] - 2000)) &&
                        sameContent(row, e))),
          )
          .firstOrNull;
      if (match == null) return false;
      acknowledged.putIfAbsent(session, () => <String>{}).add(row['id']);
      claimed.add('${match['id']}');
      if (claimed.length > 1000) claimed.remove(claimed.first);
      return true;
    });
    // Pending records remain visible across stale history responses.
    return {
      ...detail,
      'events': ([...events.where((e) => e['sendStatus'] == null), ...rows]
        ..sort(
          (a, b) =>
              ((a['time'] ?? 0) as num).compareTo((b['time'] ?? 0) as num),
        )),
    };
  }
}
