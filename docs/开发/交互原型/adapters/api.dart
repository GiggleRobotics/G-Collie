import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

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
String controlPath(Json d) =>
    '/control/${Uri.encodeComponent(d['id'] as String)}';
bool canControl(Json d, String role, bool online) =>
    online &&
    role != 'view' &&
    d['archived'] != true &&
    ((d['managed'] == true && d['readOnly'] != true) ||
        (d['desktopLive'] == true && d['desktopControl'] == true));
bool isActive(Json d) =>
    ['running', 'starting', 'waiting'].contains(d['status']);

// Preview-only in-memory transport. No HTTP client or real credentials.
class CollieApi {
  final Uri base;
  final String previewName, previewComputerId;
  bool previewOffline = false;
  String cookie;
  late Uri endpoint;
  String gatewayCookie = '';
  String get requestCookie => '';
  Future<void> Function(String)? saveCookie;
  final List<Json> projects = [
    {
      'name': 'G-Collie',
      'path': '/demo/G-Collie',
      'agents': ['Codex', 'Hermes', 'Claude Code'],
      'sessions': 3,
    },
    {
      'name': '个人工作台',
      'path': '/demo/work',
      'agents': ['Codex', 'Hermes'],
      'sessions': 0,
    },
  ];
  final Map<String, Json> sessions = {};
  int credits = 2;
  final Set<int> previewUsedResetCards = {};
  final Set<String> resetIds = {};
  CollieApi(
    this.base, {
    this.cookie = '',
    this.saveCookie,
    this.previewName = '工作电脑',
    this.previewComputerId = 'desktop',
  }) {
    endpoint = base;
    for (final a in ['Codex', 'Hermes', 'Claude Code']) {
      final id = '${a == 'Claude Code' ? 'claude' : a.toLowerCase()}:demo';
      sessions[id] = detail(
        id,
        a,
        previewComputerId == 'desktop' ? '整理项目开发流程' : '$previewName · 项目进展',
      );
    }
  }
  Json detail(String id, String agent, String title) => {
    'id': id,
    'nativeId': id.split(':').last,
    'agent': agent,
    'title': title,
    'project': 'G-Collie',
    'projectPath': '/demo/G-Collie',
    'cwd': '/demo/G-Collie',
    'managed': true,
    'desktopLive': true,
    'desktopControl': true,
    'status': 'idle',
    'claudeLive': agent == 'Claude Code',
    'hermesLive': agent == 'Hermes',
    'updatedAt': 1792719660000,
    'events': <Json>[
      {'id': 'u1', 'role': 'user', 'text': '帮我整理当前的工作和需求。'},
      {
        'id': 'a1',
        'role': 'assistant',
        'text': '这是模拟会话数据。页面、按钮、菜单和布局来自当前 Flutter App 的原始组件。\n\n可以继续发送消息，或从侧栏查看项目和用量。',
      },
    ],
  };
  void close() {}
  Future<Uri> browserPreview(String path) async =>
      throw ApiException('Android 文件阅读器未在浏览器实现，请在真机验收');
  Future<List<int>> imageBytes(String path) async =>
      (await rootBundle.load('assets/collie-companion-v2.png')).buffer
          .asUint8List();
  Future<Json> uploadVideo(
    String session,
    String name,
    int length,
    Stream<List<int>> bytes, {
    void Function(int, int)? onProgress,
  }) async => throw ApiException('视频上传与抽帧需在 Android 真机验收');
  Future<dynamic> call(String path, [Json? body]) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final scenario = Uri.base.queryParameters['state'];
    // Offline previews return cached demo records; controls remain disabled.
    if (previewOffline && (path.startsWith('/control/') || path == '/sessions'))
      throw ApiException('电脑暂时离线，连接后可发送');
    if (path == '/auth/status')
      return {
        'paired': true,
        'device': {'role': scenario == 'readonly' ? 'view' : 'control'},
      };
    if (path == '/auth/pair') {
      if (body?['code'] != '123456') throw ApiException('演示：请输入配对码 123456');
      return {
        'paired': true,
        'device': {'role': 'control'},
      };
    }
    if (path == '/local')
      return {
        'sessions': scenario == 'empty' ? [] : sessions.values.toList(),
        'projects': projects,
        'warnings': [],
      };
    if (path.startsWith('/local/')) {
      final parts = path.substring(7).split('/');
      final id = Uri.decodeComponent(parts.first);
      if (parts.length > 1 && parts[1] == 'resources') return {'resources': []};
      return sessions[id] ?? (throw ApiException('会话不存在'));
    }
    if (path == '/sessions') {
      final id =
          '${body?['agent'] == 'Claude Code' ? 'claude' : body?['agent'].toString().toLowerCase()}:${requestId()}';
      final d = detail(id, body?['agent'] ?? 'Codex', body?['prompt'] ?? '新会话');
      d['events'] = [
        {'role': 'user', 'text': body?['prompt'] ?? ''},
        {'role': 'assistant', 'text': '已收到。这是同源 Flutter 页面中的模拟回复。'},
      ];
      sessions[id] = d;
      return {'id': id};
    }
    if (path.startsWith('/control/')) {
      final id = Uri.decodeComponent(path.substring(9));
      final d = sessions[id];
      if (d == null) throw ApiException('会话不存在');
      if (body?['action'] == 'send') {
        (d['events'] as List).add({
          'role': 'user',
          'text': body?['text'] ?? body?['prompt'] ?? '',
        });
        d['status'] = 'running';
        d['turnId'] = 'preview-turn';
        Timer(const Duration(seconds: 2), () {
          d['status'] = 'idle';
          (d['events'] as List).add({
            'role': 'assistant',
            'text': '模拟回复已完成。这里使用与 App 相同的消息组件。',
          });
        });
      } else if (body?['action'] == 'stop') {
        d['status'] = 'idle';
      }
      return {'ok': true};
    }
    if (path.startsWith('/folders'))
      return {
        'path': '/demo',
        'parent': null,
        'folders': [
          {'name': 'G-Collie', 'path': '/demo/G-Collie'},
        ],
      };
    if (path == '/projects') {
      final p = {
        'name': body?['name'],
        'path': body?['path'],
        'agents': [],
        'sessions': 0,
      };
      projects.add(p);
      return p;
    }
    if (path == '/usage/codex/reset') {
      final key = '${body?['idempotencyKey'] ?? body?['requestId']}';
      if (resetIds.add(key) && credits > 0) credits--;
      return {'outcome': 'reset'};
    }
    if (path.startsWith('/usage')) {
      final counters = {
        'input': 1200,
        'output': 300,
        'cached': 400,
        'cacheWrite': 0,
        'total': 1500,
        'cacheRate': 0.33,
      };
      final agent = {
        'total': counters,
        'today': counters,
        'month': counters,
        'daily': [],
        'monthly': [],
        'sessions': [],
        'projects': [],
        'models': [],
      };
      return {
        'generatedAt': '2026-10-23',
        'timezone': 'Asia/Shanghai',
        'agents': {
          for (final a in ['Codex', 'Hermes', 'Claude Code']) a: agent,
        },
        'codexAccount': {
          'accountKey': 'preview-account',
          'accountLabel': 'demo@example.com',
          'resetCredits': {
            'availableCount': credits,
            'credits': [
              {
                'status': 'available',
                'title': '模拟重置卡',
                'expiresAt': 1795996800,
              },
            ],
          },
          'limits': [],
          'usage': {'summary': {}, 'dailyUsageBuckets': []},
        },
      };
    }
    if (path == '/network')
      return {
        'computerName': previewName,
        'addresses': ['http://preview.invalid'],
        'tailscale': {'state': '浏览器预览不执行真实网络操作'},
      };
    if (path == '/diagnostics')
      return {
        'version': '演示',
        'uptimeSeconds': 60,
        'codex': {'controlEnabled': true},
      };
    if (path == '/devices') return {'devices': []};
    if (path == '/auth/logout') return {'ok': true};
    throw ApiException('此数据/原生能力尚未在浏览器适配：$path；请在真机核对');
  }
}
