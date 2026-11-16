import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/session_events.dart';

void main() {
  test(
    'SSE uses current gateway credentials, reconnects and stops on background',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <HttpRequest>[];
      final received = Completer<void>();
      final reconnected = Completer<void>();
      var refreshes = 0;
      server.listen((request) async {
        requests.add(request);
        expect(request.uri.path, '/api/events');
        expect(
          request.headers.value('cookie'),
          contains('gcollie_device=device'),
        );
        expect(
          request.headers.value('cookie'),
          contains('gcollie_gateway=gate'),
        );
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write('event: refresh\ndata: {}\n\n');
        await request.response.flush();
        if (requests.length == 1) {
          await request.response.close();
        } else if (!reconnected.isCompleted) {
          reconnected.complete();
        }
      });
      final api = CollieApi(
        Uri.parse('http://127.0.0.1:${server.port}'),
        cookie: 'gcollie_device=device',
      )..gatewayCookie = 'gcollie_gateway=gate';
      final events = SessionEvents(api, () {
        refreshes++;
        if (!received.isCompleted) received.complete();
      }, (_) {});
      try {
        events.start();
        events.start(); // No duplicate stream.
        await received.future.timeout(const Duration(seconds: 3));
        await reconnected.future.timeout(const Duration(seconds: 4));
        events.stop();
        final count = requests.length;
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(requests.length, count);
        expect(count, 2);
        expect(refreshes, greaterThanOrEqualTo(1));
      } finally {
        events.stop();
        api.close();
        await server.close(force: true);
      }
    },
  );
}
