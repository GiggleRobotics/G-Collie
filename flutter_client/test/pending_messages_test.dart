import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/pending_messages.dart';

void main() {
  test(
    'failed retry compares actual attachments and only trims failed text',
    () {
      final p = PendingMessages();
      p.add(
        's',
        'a',
        ' hello ',
        [],
        attachments: true,
        attachmentIds: ['image-a'],
      );
      p.update('s', 'a', 'failed');
      p.add(
        's',
        'b',
        'hello',
        [],
        attachments: true,
        attachmentIds: ['image-b'],
      );
      expect(p.sessions['s'], hasLength(2));
      p.update('s', 'b', 'failed');
      p.add(
        's',
        'c',
        'hello',
        [],
        attachments: true,
        attachmentIds: ['image-a'],
      );
      expect(p.sessions['s']!.map((r) => r['id']), ['b', 'c']);
      p.update('s', 'c', 'unknown');
      p.add(
        's',
        'd',
        'hello',
        [],
        attachments: true,
        attachmentIds: ['image-a'],
      );
      expect(p.sessions['s']!.map((r) => r['id']), ['b', 'c', 'd']);
      p.update('s', 'd', 'sent');
      p.add(
        's',
        'e',
        'hello',
        [],
        attachments: true,
        attachmentIds: ['image-a'],
      );
      expect(p.sessions['s'], hasLength(4));
    },
  );

  test('failed legacy previews with different media are not discarded', () {
    final p = PendingMessages();
    p.add('s', 'a', 'photo', [], attachments: true, media: ['preview-a']);
    p.update('s', 'a', 'failed');
    p.add('s', 'b', 'photo', [], attachments: true, media: ['preview-b']);
    expect(p.sessions['s'], hasLength(2));
    p.add('s', 'c', 'photo', [], attachments: true, media: ['preview-a']);
    expect(p.sessions['s']!.map((r) => r['id']), ['b', 'c']);
  });
  test(
    'retry replaces identical failed receipt but preserves unknown sends',
    () {
      final p = PendingMessages();
      p.add('s', 'a', 'hello', [], attachments: true);
      p.update('s', 'a', 'failed');
      p.add('s', 'b', 'hello', [], attachments: true);
      expect(p.sessions['s']!.length, 1);
      p.update('s', 'b', 'unknown');
      p.add('s', 'c', 'hello', [], attachments: true);
      expect(p.sessions['s']!.length, 2);
    },
  );

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
  test(
    'server receipt heals legacy steer image receipt without consuming a text message',
    () {
      final p = PendingMessages();
      p.add(
        'codex:s',
        'request',
        '',
        [],
        attachments: true,
        attachmentIds: ['image-id'],
      );
      p.update('codex:s', 'request', 'sent');
      final text = {
        'id': 'text',
        'role': 'user',
        'text': '继续',
        'turnId': 'turn',
        'media': [],
      };
      var d = p.merge({
        'id': 'codex:s',
        'events': [text],
        'sendReceipts': [
          {'requestId': 'request', 'turnId': 'turn'},
        ],
      });
      expect(d['events'].length, 2);
      expect(p.sessions['codex:s']!.single['turnId'], 'turn');
      final other = {
        'id': 'other-image',
        'role': 'user',
        'text': '',
        'turnId': 'turn',
        'media': ['/uploads/different/media/image.jpg'],
      };
      d = p.merge({
        'id': 'codex:s',
        'events': [text, other],
      });
      expect(p.sessions['codex:s'], hasLength(1));
      final image = {
        'id': 'image',
        'role': 'user',
        'text': '',
        'turnId': 'turn',
        'media': ['gcollie-resource:opaque-image-hash'],
        'attachmentIds': ['image-id'],
      };
      d = p.merge({
        'id': 'codex:s',
        'events': [text, other, image],
      });
      expect(d['events'].length, 3);
      expect(p.sessions['codex:s'], isEmpty);
    },
  );
  test(
    'local picture is visible before history and survives stale refreshes',
    () {
      final p = PendingMessages();
      p.add(
        'codex:s',
        'request',
        '',
        [],
        attachments: true,
        attachmentIds: ['image-id'],
        media: ['gcollie-upload:image-id'],
      );
      final d = p.merge({'id': 'codex:s', 'events': []});
      expect(d['events'].single['text'], '');
      expect(d['events'].single['media'], ['gcollie-upload:image-id']);
      expect(d['events'].single['sendStatus'], 'sending');
    },
  );
  test('missing projected turn heals only a recent exact matching message', () {
    final p = PendingMessages();
    p.add('s', 'r', '继续', []);
    p.update('s', 'r', 'sent', turnId: 'known-turn');
    final now = DateTime.now().millisecondsSinceEpoch;
    final wrongTurn = {
      'id': 'other-turn',
      'role': 'user',
      'text': '继续',
      'time': now,
      'turnId': 'different',
    };
    final old = {
      'id': 'old',
      'role': 'user',
      'text': '继续',
      'time': now - 60000,
    };
    p.merge({
      'id': 's',
      'events': [wrongTurn, old],
    });
    expect(p.sessions['s'], hasLength(1));
    p.merge({
      'id': 's',
      'events': [
        wrongTurn,
        old,
        {'id': 'new', 'role': 'user', 'text': '继续', 'time': now},
      ],
    });
    expect(p.sessions['s'], isEmpty);
  });

  test('unknown sends keep exact request by session, text and attachments', () {
    final p = PendingMessages();
    for (final request in ['file-a', 'file-b']) {
      p.add(
        's',
        request,
        'same',
        [],
        attachments: true,
        attachmentIds: [request],
      );
      p.update('s', request, 'unknown');
    }
    expect(p.unknownRequest('s', 'same', ['file-a']), 'file-a');
    expect(p.unknownRequest('s', 'same', ['file-b']), 'file-b');
    expect(p.unknownRequest('s', 'same ', ['file-b']), isNull);
    expect(p.unknownRequest('s', 'same', []), isNull);
    expect(p.unknownRequest('other', 'same', ['file-a']), isNull);
  });

  test('only an exact receipt can resolve an unconfirmed same-text send', () {
    final p = PendingMessages();
    p.add('s', 'request', 'same', []);
    final confirmed = <String>[];
    final event = {
      'role': 'user',
      'text': 'same',
      'time': DateTime.now().millisecondsSinceEpoch,
    };
    final conflicting = {...event, 'id': 'other', 'requestId': 'different'};
    final legacy = {...event, 'id': 'unidentified'};
    for (final status in ['sending', 'unknown']) {
      p.update('s', 'request', status);
      p.merge({
        'id': 's',
        'events': [conflicting, legacy],
      }, onAcknowledged: (_, text) => confirmed.add(text));
      expect(p.isAcknowledged('s', 'request'), false);
      expect(p.sessions['s']!.single['sendStatus'], status);
    }
    p.merge({
      'id': 's',
      'events': [conflicting],
      'sendReceipts': [
        {'requestId': 'request', 'turnId': 'turn'},
      ],
    }, onAcknowledged: (_, text) => confirmed.add(text));
    expect(confirmed, ['same']);
    expect(p.sessions['s']!.single['sendStatus'], 'sent');
    p.merge({
      'id': 's',
      'events': [conflicting, legacy],
    }, onAcknowledged: (_, text) => confirmed.add(text));
    expect(p.sessions['s'], isEmpty);
    expect(confirmed, ['same']);
  });

  test('exact request id reconciles transformed steer text once only', () {
    final p = PendingMessages();
    p.add('s', 'r1', '同一句', []);
    p.add('s', 'r2', '同一句', []);
    p.update('s', 'r1', 'sent', turnId: 'old-active-turn');
    p.merge({
      'id': 's',
      'events': [
        {
          'id': 'native',
          'role': 'user',
          'requestId': 'r1',
          'turnId': 'actual-turn',
          'text': 'transport-enriched',
        },
      ],
    });
    expect(p.sessions['s']!.single['id'], 'r2');
    expect(p.isAcknowledged('s', 'r1'), true);
    expect(p.isAcknowledged('s', 'r2'), false);
  });
}
