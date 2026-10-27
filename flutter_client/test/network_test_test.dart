import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/network_test.dart';
import 'package:g_collie_flutter/network_authorization.dart';

void main() {
  test(
    'network test keeps its gateway and credential together during reconnect',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        expect(
          r.headers.value(HttpHeaders.cookieHeader),
          'gcollie_gateway=first',
        );
        r.response.write('ok');
        await r.response.close();
      });
      final api = CollieApi(Uri.parse('http://100.64.0.1:4310'));
      api.endpoint = Uri.parse('http://127.0.0.1:${server.port}');
      api.gatewayCookie = 'gcollie_gateway=first';
      final test = ConnectionTest(api);
      api.endpoint = Uri.parse('http://127.0.0.1:1');
      api.gatewayCookie = 'gcollie_gateway=second';
      try {
        expect(
          utf8.decode(await test.transfer('/diagnostics/network/sample/ping')),
          'ok',
        );
      } finally {
        test.cancel();
        api.close();
        await server.close(force: true);
      }
    },
  );
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
  test(
    'cancelling a stalled network test closes the pending transport',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<void>();
      server.listen((request) {
        if (!received.isCompleted) received.complete();
      });
      final api = CollieApi(Uri.parse('http://127.0.0.1:${server.port}'));
      final test = ConnectionTest(api);
      try {
        final result = test.run((_) {});
        final rejected = expectLater(result, throwsA(anything));
        await received.future;
        test.cancel();
        await rejected;
        expect(test.cancelled, isTrue);
      } finally {
        api.close();
        await server.close(force: true);
      }
    },
  );
  test(
    'authorization does not close on preexisting Running or while a login URL remains',
    () {
      final completion = AuthorizationCompletion();
      expect(completion.observe({'state': 'Running'}), isFalse);
      expect(completion.observe({'state': 'Running'}), isFalse);
      expect(
        completion.observe({
          'state': 'Running',
          'authURL': 'https://login.tailscale.com/a/test',
        }),
        isFalse,
      );
      expect(
        completion.observe({
          'state': 'Running',
          'authURL': 'https://login.tailscale.com/a/test',
        }),
        isFalse,
      );
      expect(completion.observe({'state': 'Running'}), isFalse);
      expect(completion.observe({'state': 'Running'}), isTrue);
    },
  );
  test(
    'authorization completion requires stable recovery after a pending state',
    () {
      final completion = AuthorizationCompletion();
      expect(completion.observe({'state': 'NeedsLogin'}), isFalse);
      expect(completion.observe({'state': 'Running'}), isFalse);
      expect(completion.observe({'state': 'NeedsMachineAuth'}), isFalse);
      expect(completion.observe({'state': 'Running'}), isFalse);
      expect(completion.observe({'state': 'Running'}), isTrue);
    },
  );
}
