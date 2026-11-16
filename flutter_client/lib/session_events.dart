import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'api.dart';

/// One authenticated foreground stream. Reconnects reads, never sends messages.
class SessionEvents {
  final CollieApi api;
  final void Function() refresh;
  final void Function(Object) onError;
  SessionEvents(this.api, this.refresh, this.onError);
  HttpClient? _client;
  Timer? _retry;
  bool _active = false;
  int _generation = 0, _failures = 0;
  void start() {
    if (_active) return;
    _active = true;
    _open(++_generation);
  }

  void stop() {
    _active = false;
    _generation++;
    _retry?.cancel();
    _client?.close(force: true);
    _client = null;
  }

  Future<void> _open(int generation) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    _client = client;
    try {
      final request = await client
          .getUrl(api.endpoint.resolve('/api/events'))
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      if (api.requestCookie.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, api.requestCookie);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200 ||
          response.headers.contentType?.mimeType != 'text/event-stream') {
        throw ApiException('实时连接不可用', response.statusCode);
      }
      var event = '';
      await for (final line
          in response
              .timeout(const Duration(seconds: 40))
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!_active || generation != _generation) break;
        _failures = 0;
        if (line.startsWith('event:')) event = line.substring(6).trim();
        if (line.isEmpty) {
          if (event == 'refresh') refresh();
          event = '';
        }
      }
    } catch (error) {
      if (_active && generation == _generation) onError(error);
    } finally {
      client.close(force: true);
      if (_active && generation == _generation) {
        _failures = (_failures + 1).clamp(1, 5);
        _retry = Timer(
          Duration(seconds: 1 << (_failures - 1)),
          () => _open(generation),
        );
      }
    }
  }
}
