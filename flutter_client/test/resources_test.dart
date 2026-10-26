import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/resources.dart';

void main() {
  test(
    'inline history photo decodes locally without a resource request',
    () async {
      final api = CollieApi(Uri.parse('http://127.0.0.1:1'));
      final data = await SessionResources(
        api,
        'codex:test',
      ).image('data:image/png;base64,AQID');
      expect(data, [1, 2, 3]);
      api.close();
    },
  );

  test(
    'new photo refreshes a cached resource index within the first lookup',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var calls = 0;
      upstream.listen((request) async {
        calls++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          calls == 1
              ? '{"resources":[{"id":"old","ref":"/old.png"}]}'
              : '{"resources":[{"id":"old","ref":"/old.png"},{"id":"new","ref":"/new.png"}]}',
        );
        await request.response.close();
      });
      final api = CollieApi(Uri.parse('http://127.0.0.1:${upstream.port}'));
      try {
        final resources = SessionResources(api, 'codex:test');
        expect((await resources.find('/old.png'))?['id'], 'old');
        expect((await resources.find('/new.png'))?['id'], 'new');
        expect(calls, 2);
      } finally {
        api.close();
        await upstream.close(force: true);
      }
    },
  );
  test(
    'browser relay exposes only issued paths without device credentials',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final cookies = <String?>[];
      upstream.listen((request) async {
        cookies.add(request.headers.value('cookie'));
        request.response.headers.contentType = ContentType.html;
        request.response.write('preview OK');
        await request.response.close();
      });
      final api = CollieApi(
        Uri.parse('http://127.0.0.1:${upstream.port}/'),
        cookie: 'gcollie_device=private',
      );
      api.gatewayCookie = 'gcollie_gateway=local-private';
      final client = HttpClient();
      try {
        final url = await api.browserPreview('/preview/${'a' * 48}/view');
        final response = await (await client.getUrl(url)).close();
        expect(response.statusCode, 200);
        await response.drain<void>();
        expect(cookies, ['gcollie_gateway=local-private']);
        final forbidden = await (await client.getUrl(
          url.resolve('/api/local'),
        )).close();
        expect(forbidden.statusCode, 403);
        await forbidden.drain<void>();
        final evil = await client.getUrl(url);
        evil.headers.set('origin', 'https://unrelated.example');
        final rejected = await evil.close();
        expect(rejected.statusCode, 403);
        await rejected.drain<void>();
        expect(cookies.length, 1);
        await expectLater(
          api.browserPreview('https://evil.example'),
          throwsA(isA<ApiException>()),
        );
      } finally {
        client.close(force: true);
        api.close();
        await upstream.close(force: true);
      }
    },
  );
  test(
    'resource lookup handles Markdown image URIs with encoded spaces',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '{"resources":[{"id":"file","ref":"/tmp/my image.png"}]}',
        );
        await request.response.close();
      });
      final api = CollieApi(Uri.parse('http://127.0.0.1:${upstream.port}/'));
      try {
        expect(
          (await SessionResources(
            api,
            'codex:test',
          ).find('/tmp/my%20image.png'))?['id'],
          'file',
        );
      } finally {
        api.close();
        await upstream.close(force: true);
      }
    },
  );
}
