import 'package:flutter/services.dart';
import 'api.dart';
// Browser preview only. No native operation is performed.
class NativeBridge {
  static void Function(String)? onLink;
  static void Function()? onNetworkReady;
  static const channel = MethodChannel('gcollie/preview-disabled');
  static Future<T?> invoke<T>(String method, [Json? args]) async {
    if (method == 'initialLink' || method == 'notificationsStop') return null;
    if (method == 'notificationEnabled') return false as T;
    throw ApiException('Android 原生能力 $method 请在真机验收');
  }
  static bool embedded(Uri uri) => false;
  static Future<void> connect(CollieApi api) async {}
  static Future<bool> notificationStatus() async => false;
  static Future<void> startNotifications(CollieApi api) async {
    throw ApiException('浏览器原型不模拟 Android 通知，请在真机验收');
  }
  static Future<Json> network(String action, [String? remote]) async => {
    'state': '浏览器不支持 Android 原生网络，请在真机验收',
    'computers': [],
  };
}
