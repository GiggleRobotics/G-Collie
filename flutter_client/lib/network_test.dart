import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'api.dart';
import 'diagnostic_log.dart';

class ConnectionTest {
  final CollieApi api;
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6);
  bool cancelled = false;
  final Uri endpoint;
  final String cookie;
  ConnectionTest(this.api)
    : endpoint = api.endpoint,
      cookie = api.requestCookie;
  void cancel() {
    cancelled = true;
    client.close(force: true);
  }

  Future<List<int>> transfer(String path, {List<int>? body}) async {
    if (cancelled) throw ApiException('测试已取消');
    final correlation = requestId();
    final elapsed = Stopwatch()..start();
    int? status;
    bool completed = false;
    try {
      final r = await client
          .openUrl(body == null ? 'GET' : 'POST', endpoint.resolve('/api$path'))
          .timeout(const Duration(seconds: 6));
      if (cookie.isNotEmpty) {
        r.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      r.headers.set('x-gcollie-request-id', correlation);
      if (body != null) {
        r.headers.contentType = ContentType.binary;
        r.contentLength = body.length;
        r.add(body);
      }
      final response = await r.close().timeout(const Duration(seconds: 8));
      status = response.statusCode;
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        bytes.addAll(chunk);
        if (bytes.length > 1100000) throw ApiException('测试响应超过限制');
      }
      if (response.statusCode != 200) {
        final d = jsonDecode(utf8.decode(bytes));
        throw ApiException('${d['error'] ?? '连接测试失败'}', response.statusCode);
      }
      completed = true;
      return bytes;
    } finally {
      unawaited(
        DiagnosticLog.record(
          api.base.host,
          path,
          cancelled
              ? 'network-test-cancelled'
              : status == 200
              ? completed
                    ? 'network-test-response'
                    : 'network-test-body-interrupted'
              : status == null
              ? 'network-test-transport-error'
              : 'network-test-http-error',
          requestId: correlation,
          durationMs: elapsed.elapsedMilliseconds,
          status: status,
        ).catchError((_) {}),
      );
    }
  }

  Future<Map<String, dynamic>> run(void Function(String) progress) async {
    final timeout = Timer(const Duration(seconds: 20), cancel);
    try {
      progress('检查电脑服务可达性…');
      final start = jsonDecode(
        utf8.decode(await transfer('/diagnostics/network/start', body: [])),
      );
      final root = '/diagnostics/network/${start['id']}';
      final samples = <double>[];
      for (var i = 0; i < 5; i++) {
        progress('采样延时 ${i + 1}/5…');
        final sw = Stopwatch()..start();
        await transfer('$root/ping');
        samples.add(sw.elapsedMicroseconds / 1000);
      }
      progress('测量下载速度…');
      final down = Stopwatch()..start();
      final received = await transfer('$root/download');
      down.stop();
      progress('测量上传速度…');
      final random = Random();
      final data = List<int>.generate(
        start['bytes'] as int,
        (_) => random.nextInt(256),
      );
      final up = Stopwatch()..start();
      await transfer('$root/upload', body: data);
      up.stop();
      return {
        'time': DateTime.now().toIso8601String(),
        'averageMs': samples.reduce((a, b) => a + b) / samples.length,
        'variationMs': samples.reduce(max) - samples.reduce(min),
        'downloadMbps': received.length * 8 / max(1, down.elapsedMicroseconds),
        'uploadMbps': data.length * 8 / max(1, up.elapsedMicroseconds),
        'bytes': received.length + data.length,
      };
    } finally {
      timeout.cancel();
      client.close(force: true);
    }
  }
}
