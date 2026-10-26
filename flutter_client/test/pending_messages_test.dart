import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/pending_messages.dart';

void main() {
  test(
    'receipt survives stale reads and reconciles by turn without matching old identical text',
    () {
      final pending = PendingMessages();
      final old = {
        'id': 'old',
        'role': 'user',
        'text': '继续',
        'time': 0,
        'turnId': 'old-turn',
      };
      pending.add('codex:a', 'send-1', '继续', [old]);
      pending.update('codex:a', 'send-1', 'sent', turnId: 'turn-new');
      final first = pending.merge({
        'id': 'codex:a',
        'events': [old],
      });
      expect(first['events'].length, 2);
      expect(
        pending.merge({
          'id': 'codex:a',
          'events': [old],
        })['events'].length,
        2,
      );
      expect(pending.merge({'id': 'codex:b', 'events': []})['events'], isEmpty);
      final fresh = {
        'id': 'fresh',
        'role': 'user',
        'text': '继续',
        'time': 0,
        'turnId': 'turn-new',
      };
      expect(
        pending.merge({
          'id': 'codex:a',
          'events': [old, fresh],
        })['events'].length,
        2,
      );
      expect(pending.sessions['codex:a'], isEmpty);
    },
  );
  test(
    'new thread moves pending receipt and attachment-enriched history merges',
    () {
      final p = PendingMessages();
      p.add('draft:a', 'a', '看图', [], attachments: true);
      p.move('draft:a', 'codex:new');
      p.update('codex:new', 'a', 'sent', turnId: 'new-turn');
      expect(p.merge({'id': 'codex:new', 'events': []})['events'].length, 1);
      final d = p.merge({
        'id': 'codex:new',
        'events': [
          {
            'id': 'u',
            'role': 'user',
            'text': '看图\n附件：/tmp/image.png',
            'turnId': 'new-turn',
            'time': 0,
          },
        ],
      });
      expect(d['events'].length, 1);
      expect(p.sessions['codex:new'], isEmpty);
    },
  );
}
