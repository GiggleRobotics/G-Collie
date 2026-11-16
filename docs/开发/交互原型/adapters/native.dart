import 'package:flutter/services.dart';

import 'api.dart';

// Browser preview only. No native operation is performed.
class NativeBridge {
  static Future<String> appVersion() async => '交互原型 · 模拟版本';
  static bool previewNotifications = false;
  static void Function(String)? onLink;
  static void Function()? onNetworkReady;
  static void Function()? onNetworkChanged;
  static const channel = MethodChannel('gcollie/preview-disabled');
  static Future<T?> invoke<T>(String method, [Json? args]) async {
    if (method == 'notificationsStop') {
      previewNotifications = false;
      return null;
    }
    if (method == 'initialLink') return null;
    if (method == 'notificationEnabled') return false as T;
    throw ApiException('Android 原生能力 $method 请在真机验收');
  }

  static bool embedded(Uri uri) => false;
  static Future<void> connect(CollieApi api) async {}
  static Future<bool> notificationStatus() async => previewNotifications;
  static Future<void> startNotifications(CollieApi api) async {
    previewNotifications = true;
  }

  static Future<Json> network(String action, [String? remote]) async => {
    'state': '浏览器不支持 Android 原生网络，请在真机验收',
    'computers': [],
  };
}
