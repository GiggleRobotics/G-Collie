import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'api.dart';

class NativeBridge {
  static void Function(String)? onLink;
  static const channel = MethodChannel('dev.giggle.gcollie/native');
  static Future<T?> invoke<T>(String method, [Json? args]) =>
      channel.invokeMethod<T>(method, args);
  static Future<Json> network(String action, [String? remote]) async {
    if (!Platform.isAndroid) throw ApiException('内置网络仅支持 Android');
    final raw = await invoke<String>(
      'network$action',
      remote == null ? null : {'remote': remote},
    );
    return Map<String, dynamic>.from(jsonDecode(raw!));
  }

  static bool embedded(Uri u) =>
      u.host.endsWith('.ts.net') ||
      u.host.startsWith('100.') ||
      u.host.startsWith('fd7a:115c:a1e0:');
  static Future<void> connect(CollieApi api) async {
    if (!embedded(api.base)) return;
    final result = await network('Open', api.base.toString());
    api.endpoint = serverUri(result['url']);
    api.gatewayCookie = 'gcollie_gateway=${result['token']}';
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
