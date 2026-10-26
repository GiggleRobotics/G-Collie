import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/network_test.dart';
import 'package:g_collie_flutter/network_authorization.dart';

void main() {
  test(
    'consecutive network tests use fresh IDs and server-advertised transfer sizes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var starts = 0, uploads = 0;
      server.listen((r) async {
        final path = r.uri.path;
        if (path.endsWith('/start')) {
          starts++;
          r.response.write(
            jsonEncode({'id': 'sample-$starts', 'bytes': 256 * 1024}),
          );
        } else if (path.endsWith('/download')) {
          r.response.add(List.filled(256 * 1024, 0));
        } else if (path.endsWith('/upload')) {
          final bytes = await r.fold<int>(0, (n, c) => n + c.length);
          expect(bytes, 256 * 1024);
          uploads++;
          r.response.write(jsonEncode({'bytes': bytes}));
        } else {
          r.response.write('{"ok":true}');
        }
        await r.response.close();
      });
      final api = CollieApi(Uri.parse('http://127.0.0.1:${server.port}'));
      try {
        for (var i = 0; i < 2; i++) {
          final result = await ConnectionTest(api).run((_) {});
          expect(result['bytes'], 512 * 1024);
          expect(result['downloadMbps'], greaterThan(0));
        }
        expect(starts, 2);
        expect(uploads, 2);
      } finally {
        api.close();
        await server.close(force: true);
      }
    },
  );
  test(
    'authorization navigation stays on HTTPS and blocks app/browser schemes',
    () {
      expect(allowedAuthorizationUrl('https://login.tailscale.com/a'), isTrue);
      expect(
        allowedAuthorizationUrl('https://accounts.google.com/login'),
        isTrue,
      );
      for (final u in [
        'intent://login',
        'http://login.tailscale.com/',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'https://user:pass@example.com',
      ]) {
        expect(allowedAuthorizationUrl(u), isFalse);
      }
    },
  );
}
