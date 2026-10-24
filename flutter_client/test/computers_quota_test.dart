import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:g_collie_flutter/computers.dart';
import 'package:g_collie_flutter/quota_notice.dart';
import 'package:g_collie_flutter/upgrade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'paired computers preserve roles and credentials independently',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();
      final store = ComputerStore(storage);
      final a = Uri.parse('http://192.168.1.2:4310/'),
          b = Uri.parse('http://192.168.1.3:4310/');
      await storage.write(key: 'cookie:$a', value: 'device=a');
      await storage.write(key: 'cookie:$b', value: 'device=b');
      await store.remember(a, 'control', name: '工作电脑');
      await store.remember(b, 'view', name: '笔记本');
      await store.remember(a, 'control');
      expect((await store.read()).length, 2);
      expect((await store.read()).first['name'], '工作电脑');
      expect(await storage.read(key: 'server'), '$a');
      await store.remember(b, 'view', name: '更新后的笔记本', select: false);
      expect(await storage.read(key: 'server'), '$a');
      await store.forget(a);
      expect(await storage.read(key: 'cookie:$a'), isNull);
      expect(await storage.read(key: 'cookie:$b'), 'device=b');
      expect(await storage.read(key: 'server'), '$b');
      expect((await store.read()).single['role'], 'view');
    },
  );
  test('quota does not invent a missing window or confuse review limits', () {
    expect(quotaExhausted(null), false);
    final data = {
      'limits': [
        {
          'id': 'review',
          'windows': [
            {'windowMinutes': 300, 'usedPercent': 100},
          ],
        },
        {
          'id': 'codex',
          'windows': [
            {'windowMinutes': 10080, 'usedPercent': 78, 'resetsAt': 123},
          ],
        },
      ],
    };
    expect(codexWindows(data).length, 1);
    expect(quotaExhausted(data), false);
    expect(
      quotaExhausted({
        'limits': [
          {
            'id': 'codex',
            'windows': [
              {'windowMinutes': 300, 'usedPercent': 100},
            ],
          },
        ],
      }),
      true,
    );
    expect(quotaCountdown(null, DateTime.now()), '重置时间暂未提供');
    expect(quotaCountdown(0, DateTime.now()), '正在更新额度');
  });
  test(
    'upgrade uses HTTPS official destinations and blocks intent or local URLs',
    () {
      expect(allowedUpgradeUrl('https://chatgpt.com/#pricing'), true);
      expect(allowedUpgradeUrl('https://auth.openai.com/login'), true);
      for (final url in [
        'http://chatgpt.com',
        'https://chatgpt.com.evil.example',
        'https://user:pass@chatgpt.com',
        'intent://pay',
        'http://127.0.0.1:4310',
      ]) {
        expect(allowedUpgradeUrl(url), false, reason: url);
      }
    },
  );
}
