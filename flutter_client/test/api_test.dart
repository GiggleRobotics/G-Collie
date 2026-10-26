import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';

void main() {
  test('reject non-server URLs and preserve host port', () {
    expect(
      serverUri('http://192.168.1.2:4310').toString(),
      'http://192.168.1.2:4310/',
    );
    for (final value in [
      'file:///tmp/x',
      'http://user:pass@host',
      'http://host/api',
      'localhost:4310',
    ]) {
      expect(() => serverUri(value), throwsA(isA<ApiException>()));
    }
  });
  test('route actions to original agent and encode native identifiers', () {
    expect(
      controlPath({'desktopLive': true, 'nativeId': 'a/b', 'hermesLive': true}),
      '/hermes/a%2Fb',
    );
    expect(
      controlPath({'desktopLive': true, 'nativeId': 'abc'}),
      '/desktop/abc',
    );
    expect(
      controlPath({'managed': true, 'id': 'managed:abc'}),
      '/control/managed%3Aabc',
    );
  });
  test('Claude sessions use Claude control endpoint', () {
    expect(
      controlPath({'desktopLive': true, 'claudeLive': true, 'nativeId': 'abc'}),
      '/claude/abc',
    );
  });
  test('read-only, disconnected and archived devices cannot control', () {
    final detail = {'desktopLive': true, 'desktopControl': true};
    expect(canControl(detail, 'control', true), isTrue);
    expect(canControl(detail, 'view', true), isFalse);
    expect(canControl(detail, 'control', false), isFalse);
    expect(canControl({...detail, 'archived': true}, 'control', true), isFalse);
  });
  test(
    'pairing persists cookie, authenticated request sends it, 401 propagates without retry',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var count = 0;
      server.listen((r) async {
        count++;
        r.response.headers.contentType = ContentType.json;
        if (r.uri.path == '/api/auth/pair') {
          expect(
            jsonDecode(await utf8.decoder.bind(r).join())['code'],
            '123456',
          );
          r.response.cookies.add(
            Cookie('gcollie_device', 'test-device')..httpOnly = true,
          );
          r.response.write('{"device":{"role":"control"}}');
        } else {
          expect(r.cookies.single.value, 'test-device');
          r.response.statusCode = 401;
          r.response.write('{"error":"配对已撤销"}');
        }
        await r.response.close();
      });
      String? stored;
      final api = CollieApi(
        Uri.parse('http://127.0.0.1:${server.port}'),
        saveCookie: (value) async {
          stored = value;
        },
      );
      try {
        await api.call('/auth/pair', {'code': '123456'});
        expect(stored, 'gcollie_device=test-device');
        await expectLater(
          api.call('/local'),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
        );
        expect(count, 2);
      } finally {
        api.close();
        await server.close(force: true);
      }
    },
  );
  test(
    'reachability verifies health identity and preserves gateway authorization',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var valid = true;
      server.listen((request) async {
        expect(request.uri.path, '/healthz');
        expect(request.cookies.single.value, 'test-gateway');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          valid ? '{"ok":true,"version":"test"}' : '{"ok":true}',
        );
        await request.response.close();
      });
      final api = CollieApi(Uri.parse('http://127.0.0.1:${server.port}'))
        ..gatewayCookie = 'gcollie_gateway=test-gateway';
      expect(await api.reachable(), true);
      valid = false;
      expect(await api.reachable(), false);
      api.close();
      await server.close(force: true);
    },
  );
}
