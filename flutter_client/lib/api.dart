import 'dart:convert';
import 'dart:io';
import 'dart:math';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

Uri serverUri(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw ApiException('请输入完整电脑地址，例如 http://192.168.1.10:4310');
  }
  if (uri.path != '' && uri.path != '/') throw ApiException('地址只能包含协议、主机和端口');
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '/',
  );
}

String requestId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
String controlPath(Json detail) {
  if (detail['desktopLive'] == true && detail['managed'] != true) {
    return '/${detail['claudeLive'] == true
        ? 'claude'
        : detail['hermesLive'] == true
        ? 'hermes'
        : 'desktop'}/${Uri.encodeComponent(detail['nativeId'] as String)}';
  }
  return '/control/${Uri.encodeComponent(detail['id'] as String)}';
}

bool canControl(Json d, String role, bool online) =>
    online &&
    role != 'view' &&
    d['archived'] != true &&
    ((d['managed'] == true && d['readOnly'] != true) ||
        (d['desktopLive'] == true && d['desktopControl'] == true));
bool isActive(Json d) =>
    ['running', 'starting', 'waiting'].contains(d['status']);

class CollieApi {
  final Uri base;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  String cookie;
  Uri endpoint;
  String gatewayCookie = '';
  String get requestCookie =>
      [cookie, gatewayCookie].where((v) => v.isNotEmpty).join('; ');
  Future<void> Function(String)? saveCookie;
  CollieApi(this.base, {this.cookie = '', this.saveCookie}) : endpoint = base;
  HttpServer? _browser;
  final Set<String> _previewPaths = {};
  void close() {
    _browser?.close(force: true);
    _client.close(force: true);
  }

  // Browsers have a separate cookie jar. Relay only explicitly issued file
  // tickets through loopback, including when the tailnet gateway is in use.
  Future<Uri> browserPreview(String path) async {
    final match = RegExp(r'^/preview/([a-f0-9]{48})/view$').firstMatch(path);
    if (match == null) throw ApiException('电脑返回的预览地址无效');
    _previewPaths.add('/preview/${match[1]}/');
    if (_browser == null) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _browser = server;
      server.listen((request) async {
        try {
          final origin = request.headers.value('origin');
          final ownOrigin = 'http://127.0.0.1:${server.port}';
          final allowed =
              _previewPaths.any(request.uri.path.startsWith) ||
              [
                '/preview-assets/pdf.mjs',
                '/preview-assets/pdf.worker.mjs',
              ].contains(request.uri.path);
          if (request.uri.hasScheme ||
              request.uri.hasAuthority ||
              !['GET', 'HEAD'].contains(request.method) ||
              request.headers.value('host') != '127.0.0.1:${server.port}' ||
              (origin != null && origin != ownOrigin) ||
              !allowed) {
            request.response.statusCode = 403;
            await request.response.close();
            return;
          }
          final upstream = await _client.openUrl(
            request.method,
            endpoint.resolve(request.uri.toString()),
          );
          upstream.followRedirects = false;
          if (gatewayCookie.isNotEmpty) {
            upstream.headers.set(HttpHeaders.cookieHeader, gatewayCookie);
          }
          for (final name in ['range', 'if-range']) {
            final value = request.headers.value(name);
            if (value != null) upstream.headers.set(name, value);
          }
          final response = await upstream.close();
          request.response.statusCode = response.statusCode;
          for (final name in [
            'content-type',
            'content-length',
            'content-range',
            'accept-ranges',
            'content-disposition',
            'content-security-policy',
            'referrer-policy',
            'x-content-type-options',
          ]) {
            final value = response.headers.value(name);
            if (value != null) request.response.headers.set(name, value);
          }
          request.response.headers.set('cache-control', 'no-store');
          await request.response.addStream(response);
          await request.response.close();
        } catch (_) {
          request.response.statusCode = 502;
          request.response.write('电脑连接已断开，请返回 G-Collie 重试。');
          await request.response.close();
        }
      });
    }
    return Uri.parse('http://127.0.0.1:${_browser!.port}$path');
  }

  Future<List<int>> imageBytes(String path) async {
    final request = await _client.getUrl(endpoint.resolve('/api$path'));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.cookieHeader, requestCookie);
    final response = await request.close();
    if (response.statusCode != 200) throw ApiException('图片暂时无法加载');
    final bytes = <int>[];
    await for (final part in response) {
      bytes.addAll(part);
      if (bytes.length > 15 * 1024 * 1024) throw ApiException('图片超过 15 MB');
    }
    return bytes;
  }

  Future<Json> uploadVideo(
    String session,
    String name,
    int length,
    Stream<List<int>> bytes, {
    void Function(int, int)? onProgress,
  }) async {
    final url = endpoint
        .resolve('/api/attachments/media')
        .replace(queryParameters: {'session': session, 'name': name});
    HttpClientRequest? request;
    try {
      request = await _client.postUrl(url);
      request.followRedirects = false;
      request.contentLength = length;
      request.headers.contentType = ContentType.binary;
      if (requestCookie.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, requestCookie);
      }
      var sent = 0;
      await request
          .addStream(
            bytes.map((chunk) {
              sent += chunk.length;
              onProgress?.call(sent, length);
              return chunk;
            }),
          )
          .timeout(const Duration(minutes: 3));
      final response = await request.close().timeout(
        const Duration(minutes: 3),
      );
      final data =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw ApiException('${data['error'] ?? '视频上传失败'}', response.statusCode);
      }
      return data;
    } catch (e) {
      request?.abort();
      if (e is ApiException) rethrow;
      throw ApiException('视频上传中断，请重新选择；不会自动重发消息');
    }
  }

  Future<dynamic> call(String path, [Json? body]) async {
    try {
      return await _call(path, body).timeout(const Duration(seconds: 35));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        body == null ? '电脑连接中断，任务状态未知' : '请求结果未知，请刷新确认；不会自动重发',
      );
    }
  }

  Future<dynamic> _call(String path, Json? body) async {
    final request = await _client.openUrl(
      body == null ? 'GET' : 'POST',
      endpoint.resolve('/api$path'),
    );
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (requestCookie.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, requestCookie);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    for (final value in response.cookies) {
      if (value.name == 'gcollie_device') {
        cookie = value.value.isEmpty ? '' : '${value.name}=${value.value}';
        await saveCookie?.call(cookie);
      }
    }
    final text = await utf8.decoder.bind(response).join();
    dynamic data;
    try {
      data = jsonDecode(text);
    } catch (_) {
      throw ApiException('电脑返回了无效响应，请检查服务地址', response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        data is Map ? '${data['error'] ?? '请求失败'}' : '请求失败',
        response.statusCode,
      );
    }
    return data;
  }
}
