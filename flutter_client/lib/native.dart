import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'api.dart';

class NativeBridge {
  static void Function(String)? onLink;
  static void Function()? onNetworkReady;
  static const channel = MethodChannel('dev.giggle.gcollie/native');
  static Future<T?> invoke<T>(String method, [Json? args]) {
    final result = channel.invokeMethod<T>(method, args);
    return method.startsWith('network')
        ? result.timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw ApiException('内置网络响应超时，请重新连接'),
          )
        : result;
  }

  static Future<Json> network(String action, [String? remote]) async {
    if (!Platform.isAndroid) throw ApiException('内置网络仅支持 Android');
    final raw = await invoke<String>(
      'network$action',
      remote == null ? null : {'remote': remote},
    );
    return Map<String, dynamic>.from(jsonDecode(raw!));
  }

  static bool embedded(Uri u) {
    final ip = InternetAddress.tryParse(u.host);
    if (u.host.endsWith('.ts.net')) return true;
    if (ip == null) return false;
    final bytes = ip.rawAddress;
    return bytes.length == 4
        ? bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127
        : u.host.startsWith('fd7a:115c:a1e0:');
  }

  static Future<void> connect(CollieApi api) async {
    if (!embedded(api.base)) return;
    // A system Tailscale VPN is also valid; do not force a second login.
    final probe = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await probe
          .getUrl(api.base.resolve('/healthz'))
          .timeout(const Duration(seconds: 3));
      req.followRedirects = false;
      final response = await req.close().timeout(const Duration(seconds: 3));
      final data = await response
          .transform(const SystemEncoding().decoder)
          .join()
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200 &&
          data.contains('"ok":true') &&
          data.contains('"version"')) {
        api.endpoint = api.base;
        api.gatewayCookie = '';
        return;
      }
    } catch (_) {
      // Otherwise route only this app through its own embedded Tailscale node.
    } finally {
      probe.close(force: true);
    }
    await waitForNetwork(() => network('Status'));
    Json? result;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        result = await network('Open', api.base.toString());
        break;
      } on PlatformException catch (e) {
        if (attempt == 2 || !(e.message ?? '').contains('无法访问电脑')) {
          throw ApiException(e.message ?? '私有网络连接失败');
        }
        // Read-only health probe: allow DERP/WireGuard paths to settle after login.
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (result == null) throw ApiException('无法连接电脑，请稍后重试');
    api.endpoint = serverUri(result['url']);
    api.gatewayCookie = 'gcollie_gateway=${result['token']}';
  }

  static Future<void> waitForNetwork(
    Future<Json> Function() status, {
    Future<void> Function(Duration) pause = Future<void>.delayed,
  }) async {
    Json state = {};
    // Restoring the persisted login is asynchronous after process startup.
    for (var attempt = 0; attempt < 30; attempt++) {
      state = await status();
      if (state['state'] == 'Running') break;
      if (attempt >= 5 &&
          state['state'] == 'NeedsLogin' &&
          state['authURL'] != null) {
        break;
      }
      await pause(const Duration(milliseconds: 500));
    }
    if (state['state'] != 'Running') {
      throw ApiException(
        state['state'] == 'NeedsLogin'
            ? '请在右上角“远程连接”登录，或启用系统 Tailscale 后重新连接'
            : '私有网络仍在连接，请稍后重试（${state['state']}）',
      );
    }
  }

  static Future<bool> notificationStatus() async =>
      await invoke<bool>('notificationStatus') ?? false;
  static Future<void> startNotifications(CollieApi api) async {
    if (await invoke<bool>('notificationPermission') != true) {
      throw ApiException('未获得通知权限，请在系统设置中允许后重试');
    }
    await invoke<void>('notificationsStart', {
      'origin': api.endpoint.toString().replaceFirst(RegExp(r'/$'), ''),
      'cookie': api.requestCookie,
      'remote': api.base.toString().replaceFirst(RegExp(r'/$'), ''),
    });
  }
}
