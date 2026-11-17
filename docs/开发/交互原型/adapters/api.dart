import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int status;
  final String? code;
  final String? outcome;
  ApiException(this.message, [this.status = 0, this.code, this.outcome]);
  @override
  String toString() => message;
}

/// A received HTTP rejection can still describe a write with unknown outcome.
/// Prefer the server's structured result over its status or localized message.
bool operationResultUnknown(Object error) {
  if (error is! ApiException) return true;
  if (error.outcome == 'unknown' ||
      error.code == 'hermes_result_unknown' ||
      error.code == 'desktop_result_unknown') {
    return true;
  }
  return error.status == 0 ||
      error.status >= 500 ||
      RegExp('结果未知|结果可能未知|已提交|超时').hasMatch('$error');
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
  // Local-only preview metadata; never reads production attachment caches.
  final Map<String, Json> attachmentPreviews = {};
  Future<bool> reachable() async => !previewOffline;
  Future<void> recordFailure(
    String path,
    String reason, [
    String? correlation,
  ]) async {}

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
    for(final agent in ['Codex','Hermes','Claude Code']) {
      final prefix = agent == 'Claude Code' ? 'claude' : agent.toLowerCase();
      for(var i=2;i<=5;i++) {
        final id = '$prefix:demo-$i';
        sessions[id]=detail(id,agent,'$agent · 第 $i 个最近会话')..['updatedAt']=1792719660000-i*60000;
      }
    }
    configurePreviewScenario();
    if (Uri.base.queryParameters['detail'] == 'multi-select') {
      final pending = sessions['hermes:demo']?['pending'];
      if (pending is Map) { for(final q in pending['params']['questions'] as List) { q['multiSelect'] = true; } }
    }
  }
  void configurePreviewScenario() {
    final page = Uri.base.queryParameters['page'];
    final focus = Uri.base.queryParameters['detail'];
    final demo = sessions[page == 'chat' && ['image-view','image-view-multiple','image-view-failure','image-view-command'].contains(focus) ? 'codex:demo' : 'hermes:demo'];
    if (demo == null) return;
    if (page == 'video')
      demo['events'] = [
        {
          'id': 'video-title',
          'role': 'assistant',
          'text': '示例视频：播放前显示真实首帧，点击原位播放，右上角可全屏。',
        },
        {
          'id': 'video-demo',
          'role': 'assistant',
          'text': '[示例视频](/demo/preview.mp4)',
        },
      ];
    if (['gallery', 'gallery-preview', 'single-image', 'media-failure', 'media-loading'].contains(focus)) {
      demo['events'] = [
        {'id':'media-note','role':'assistant','text':'图片演示：完整主图、侧边缩略图、点击在 App 内预览。'},
        {'id':'images','role':'assistant','media': focus == 'single-image' ? ['/demo/image-1.jpg'] : ['/demo/image-1.jpg','/demo/image-2.jpg','/demo/image-3.jpg']},
      ];
    }
    if (focus == 'long-history') {
      demo['events'] = List.generate(260, (i) => {'id':'history-$i','role':i.isEven?'user':'assistant','text':'第 ${i+1} 条演示记录\n向上滑查看历史，输入框上方显示跳到最新消息箭头。'});
    }
    if (['image-view','image-view-multiple','image-view-failure','image-view-command'].contains(focus)) {
      demo['events'] = [
        {'id':'image-context','role':'assistant','text':'我查看了会话中的图片，继续核对画面细节。'},
        {'id':'view-image','role':'tool','name':focus == 'image-view-command' ? 'exec_command' : 'view_image','commands':focus == 'image-view-command' ? [{'command':'printf 仅演示，不执行','output':'已查看演示图片','exitCode':0}] : [],'imageView':true,'imageCount':focus == 'image-view-multiple' ? 3 : 1,'status':focus == 'image-view-failure' ? 'failed' : 'completed','input':'view_image · 演示图片','text':focus == 'image-view-failure' ? '图片暂时不可用' : '已读取图像内容','media':focus == 'image-view-multiple' ? ['/demo/image-1.jpg','/demo/image-2.jpg','/demo/image-3.jpg'] : ['/demo/image-1.jpg']},
      ];
    }
    if (focus == 'tool-records') {
      demo['events'] = [
        for (final state in ['completed','pending','failed'])
          {'id':'tool-$state','role':'tool','name':'终端','status':state,'input':'printf "仅演示，不执行"','text':state == 'failed'?'示例：命令未成功，请检查参数':'示例输出：未执行真实命令','durationMs':3200},
      ];
    }
    if (focus == 'session-menu') demo['managed'] = false;
    if (['approval', 'question', 'secret'].contains(page)) {
      demo['events'] = [
        {'id':'request-context','role':'assistant','text':page=='question' ? '继续整理之前，先确认你希望的输出方式。' : page=='secret' ? '这一步需要补充访问口令，请在下方单独填写。原型中请勿输入真实信息。' : '继续前需要你确认这次操作；原型不会执行真实命令。'},
      ];
      demo['status'] = 'waiting';
      demo['pending'] = {
        'id': 'preview-request',
        'kind': page,
        'params': page == 'approval'
            ? {
                'command': 'printf "示例命令"',
                'reason': '助手希望执行下方命令，请确认后继续。',
                'availableDecisions': ['accept', 'decline'],
              }
            : page == 'question'
            ? {
                'questions': [
                  {
                    'id': 'answer',
                    'question': '请选择演示输出方式',
                    'options': [
                      {'label': '简洁', 'description': '只保留结论与必要步骤'},
                      {'label': '详细', 'description': '包含原因、步骤和验证方式'},
                    ],
                  },
                ],
              }
            : {'prompt': '演示安全输入，不使用真实密码', 'secretType': 'secret'},
      };
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
  Future<Uri> browserPreview(String path) async {
    if (path == '/preview/demo/view')
      return Uri.base.resolve(Uri.base.queryParameters['detail']=='video-portrait' ? 'assets/assets/ui/demo-portrait.mp4' : 'assets/assets/ui/demo-video.mp4');
    throw ApiException('此原生文件能力需在 Android 真机验收');
  }

  Future<List<int>> imageBytes(String path) async {
    if (Uri.base.queryParameters['detail'] == 'media-loading') await Future<void>.delayed(const Duration(seconds: 6));
    if (Uri.base.queryParameters['detail'] == 'media-failure') throw ApiException('演示：媒体加载失败');
    return (await rootBundle.load(
    path.endsWith('/poster')
        ? (Uri.base.queryParameters['detail']=='video-portrait' ? 'assets/ui/demo-portrait-poster.jpg' : 'assets/ui/demo-video-poster.jpg')
        : path.contains('image-2') ? 'assets/ui/demo-video-poster.jpg' : path.contains('image-3') ? 'assets/collie-mark-v2.png' : 'assets/collie-companion-v2.png',
  )).buffer.asUint8List();
  }
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
        'device': {'role': 'control'},
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
    if(path.endsWith('/codex-capabilities')) return {'mode':'default','modes':{'data':{'data':[{'mode':'plan'},{'mode':'default'}]}},'plugins':{'data':{'marketplaces':[]}},'skills':[{'id':'demo:documents','name':'documents','plugin':'Documents'}],'goal':{'data':{'goal':null}}};
    if(path.endsWith('/goal')||path.endsWith('/mode')) return {'ok':true};
    if (path.startsWith('/local/')) {
      final parts = path.substring(7).split('/');
      final id = Uri.decodeComponent(parts.first);
      if (parts.length > 1 && parts[1] == 'resources') {
        if(parts.last=='preview' && Uri.base.queryParameters['detail']=='video-failure') throw ApiException('演示：视频文件不可用，请重试');
        if (parts.last == 'preview') return {'path': '/preview/demo/view'};
        return {
          'resources': [
            for (var i=1;i<=3;i++) {'id':'image-$i','name':'示例图片-$i.jpg','ref':'/demo/image-$i.jpg','image':true},
            if (!['image-view','image-view-multiple','image-view-failure'].contains(Uri.base.queryParameters['detail'])) {
              'id': 'preview-video',
              'name': '示例视频.mp4',
              'ref': '/demo/preview.mp4',
              'image': false,
            },
          ],
        };
      }
      return sessions[id] ?? (throw ApiException('会话不存在'));
    }
    if (path.startsWith('/share/')) return {'url':'/share/preview-only','key':'preview-only'};
    if (path.startsWith('/hermes/')) {
      final nativeId=Uri.decodeComponent(path.substring('/hermes/'.length));
      final demo=sessions.values.firstWhere((d)=>d['nativeId']==nativeId);
      if(body?['action']=='rename') demo['title']=body?['title'];
      if(body?['action']=='archive') demo['archived']=true;
      return {'ok':true};
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
      if (body?['action'] == 'answer') {
        d.remove('pending');
        d['status'] = 'idle';
        return {'ok': true};
      }
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
        'path': Uri.parse(path).queryParameters['path'] ?? '/demo',
        'parent': Uri.parse(path).queryParameters['path'] == null ? null : '/demo',
        'folders': Uri.parse(path).queryParameters['path'] == null ? [{'name': 'G-Collie', 'path': '/demo/G-Collie'}] : [],
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
