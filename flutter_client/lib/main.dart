import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'ui.dart';
import 'native.dart';

void main() => runApp(const CollieApp());
const storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
const green = Color(0xff216957);

final appTheme = ValueNotifier<ThemeMode>(ThemeMode.system);
final appLarge = ValueNotifier<bool>(false);

class CollieApp extends StatelessWidget {
  const CollieApp({super.key});
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: companionGreen,
        brightness: brightness,
        surface: dark ? const Color(0xff212121) : Colors.white,
      ),
      scaffoldBackgroundColor: dark ? const Color(0xff212121) : Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xff212121) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xff212121) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        titleTextStyle: TextStyle(
          fontSize: 20,
          color: dark ? Colors.white : ink,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: dark ? Colors.white : ink,
          height: 1.5,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: dark ? Colors.white : ink),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(15)),
          borderSide: BorderSide(color: Color(0xffdddddd)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(15)),
          borderSide: BorderSide(color: Color(0xffdddddd)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(15)),
          borderSide: BorderSide(color: Color(0xff555555)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: appTheme,
    builder: (_, mode, _) => MaterialApp(
      title: 'G-Collie',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: mode,
      home: const ConnectionPage(),
    ),
  );
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});
  @override
  State<ConnectionPage> createState() => _ConnectionState();
}

class _ConnectionState extends State<ConnectionPage> {
  final address = TextEditingController(),
      code = TextEditingController(),
      name = TextEditingController();
  bool busy = true;
  String? error;
  CollieApi? api;
  String? pendingSession;
  @override
  void initState() {
    super.initState();
    NativeBridge.onLink = (value) async {
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await receiveLink(value);
    };
    NativeBridge.channel.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) {
        NativeBridge.onLink?.call(call.arguments as String);
      }
    });
    restore();
  }

  Future<void> restore() async {
    try {
      final initial = await NativeBridge.invoke<String>('initialLink');
      if (initial != null) {
        await receiveLink(initial);
        return;
      }
      final theme = await storage.read(key: 'theme');
      appLarge.value = await storage.read(key: 'fontLarge') == 'true';
      appTheme.value =
          ThemeMode.values.where((v) => v.name == theme).firstOrNull ??
          ThemeMode.system;
      final saved = await storage.read(key: 'server');
      if (saved != null) {
        address.text = saved;
        final client = await makeApi(
          saved,
          await storage.read(key: 'cookie:$saved') ?? '',
        );
        final result = await client.call('/auth/status');
        if (result['paired'] == true) {
          await enter(client, result['device']['role']);
          return;
        }
        client.close();
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) {
      setState(() => busy = false);
      if (address.text.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => chooseAddress());
      }
    }
  }

  Future<void> receiveLink(String value) async {
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final uri = Uri.parse(value);
      final base = serverUri(value);
      address.text = '$base';
      pendingSession = uri.queryParameters['session'];
      await storage.write(key: 'server', value: '$base');
      final client = await makeApi(
        '$base',
        await storage.read(key: 'cookie:$base') ?? '',
      );
      final status = await client.call('/auth/status');
      if (status['paired'] == true) {
        await enter(client, status['device']['role']);
        return;
      }
      client.close();
      final secret = Uri.splitQueryString(uri.fragment)['pair'];
      if (secret != null) {
        code.text = secret;
        await pair();
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseAddress() async {
    final field = TextEditingController(text: address.text);
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('连接电脑'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '内置私有网络：无需另装 Tailscale。先在本应用授权入网，再输入电脑 G-Collie 显示的私有网络地址或完整配对链接。\n\n例如 http://100.x.x.x:4310',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: field,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: '电脑地址 / 配对链接'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('内置远程连接'),
                  content: const SizedBox(width: 400, child: NetworkPane()),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('内置网络'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, field.text.trim()),
            child: const Text('连接'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    field.dispose();
    if (selected == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final raw = Uri.parse(
        selected.contains('://') ? selected : 'http://$selected',
      );
      final normalized =
          raw.port == 80 && raw.scheme == 'http' && NativeBridge.embedded(raw)
          ? raw.replace(port: 4310)
          : raw;
      final base = serverUri(normalized.toString());
      address.text = '$base';
      await storage.write(key: 'server', value: '$base');
      final pairCode = Uri.splitQueryString(raw.fragment)['pair'];
      if (pairCode != null) {
        code.text = pairCode;
        await pair();
        return;
      }
      final client = await makeApi(
        '$base',
        await storage.read(key: 'cookie:$base') ?? '',
      );
      final result = await client.call('/auth/status');
      if (result['paired'] == true) {
        await enter(client, result['device']['role']);
      } else {
        client.close();
      }
    } catch (e) {
      api?.close();
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<CollieApi> makeApi(String value, String cookie) async {
    final base = serverUri(value);
    api = CollieApi(
      base,
      cookie: cookie,
      saveCookie: (c) => storage.write(key: 'cookie:$base', value: c),
    );
    await NativeBridge.connect(api!);
    return api!;
  }

  Future<void> enter(CollieApi client, String role) async {
    if (!mounted) return;
    setState(() => busy = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            Workspace(api: client, role: role, initialSession: pendingSession),
      ),
    );
    pendingSession = null;
    client.close();
    if (mounted) {
      setState(() {
        busy = false;
        code.clear();
      });
    }
  }

  Future<void> pair() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final raw = Uri.tryParse(address.text.trim());
      final linked = raw == null
          ? null
          : Uri.splitQueryString(raw.fragment)['pair'];
      final base = serverUri(
        raw == null ? address.text : raw.replace(fragment: '').toString(),
      );
      final client = await makeApi('$base', '');
      final result = await client.call('/auth/pair', {
        'code': linked ?? code.text.trim(),
        'name': name.text.trim().isEmpty ? '我的手机' : name.text.trim(),
      });
      await storage.write(key: 'server', value: '$base');
      await enter(client, result['device']['role']);
    } catch (e) {
      api?.close();
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() {
    address.dispose();
    code.dispose();
    name.dispose();
    api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 40,
      title: const Text(
        'G-Collie',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
      ),
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == '切换电脑') {
              chooseAddress();
            } else {
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('内置远程连接'),
                  content: const SizedBox(width: 400, child: NetworkPane()),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              );
            }
          },
          itemBuilder: (_) => [
            '内置网络',
            '切换电脑',
          ].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
        ),
      ],
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.sizeOf(context).height * .1,
          24,
          24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'G-Collie',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 38),
                const Text(
                  '配对你的电脑',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                muted(context, '在已连接的电脑打开“手机与配对”，扫码或输入短期配对码。', size: 13),
                const SizedBox(height: 18),
                muted(context, '设备名称', size: 13),
                const SizedBox(height: 8),
                TextField(
                  controller: name,
                  enabled: !busy,
                  maxLength: 80,
                  decoration: InputDecoration(
                    hintText: '例如：我的手机',
                    counterText: '',
                    filled: true,
                    fillColor: panelColor(context),
                  ),
                ),
                const SizedBox(height: 18),
                muted(context, '配对码', size: 13),
                const SizedBox(height: 8),
                TextField(
                  controller: code,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '6 位配对码',
                    filled: true,
                    fillColor: panelColor(context),
                  ),
                ),
                const SizedBox(height: 15),
                FilledButton(
                  onPressed: busy || code.text.trim().isEmpty ? null : pair,
                  style: FilledButton.styleFrom(
                    backgroundColor: ink,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(busy ? '正在连接…' : '配对设备'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xffb54c3b)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class Workspace extends StatefulWidget {
  final CollieApi api;
  final String role;
  final String? initialSession;
  const Workspace({
    super.key,
    required this.api,
    required this.role,
    this.initialSession,
  });
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  final draft = TextEditingController();
  final scroll = ScrollController();
  List<dynamic> sessions = [], projects = [], warnings = [];
  Json? detail;
  String error = '';
  bool online = false,
      loading = false,
      busy = false,
      polling = false,
      active = true,
      leaving = false;
  int generation = 0, ticks = 0;
  Timer? timer;
  final answers = <String, String>{};
  final answerControllers = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    if (widget.initialSession != null) open(widget.initialSession!);
    NativeBridge.invoke<bool>('notificationEnabled')
        .then((enabled) {
          if (enabled == true && mounted) {
            NativeBridge.startNotifications(widget.api);
          }
        })
        .catchError((_) {
          return null;
        });
    timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) {
      load();
      poll();
    } else {
      setState(() => online = false);
    }
  }

  void failure(Object e) {
    if (!mounted) return;
    if (e is ApiException && e.status == 401) {
      if (!leaving) {
        leaving = true;
        Navigator.pop(context);
      }
      return;
    }
    if (leaving) return;
    setState(() {
      error = '$e';
      online = false;
      if (detail != null) {
        detail = {
          ...detail!,
          'desktopLive': false,
          'readOnly': true,
          'status': 'unknown',
        };
      }
    });
  }

  Future<void> load() async {
    try {
      final data = await widget.api.call('/local');
      if (mounted) {
        setState(() {
          sessions = data['sessions'] ?? [];
          projects = data['projects'] ?? [];
          warnings = data['warnings'] ?? [];
          online = active;
          error = '';
        });
      }
    } catch (e) {
      failure(e);
    }
  }

  Future<void> open(String id) async {
    final token = ++generation;
    setState(() {
      loading = true;
      error = '';
      detail = null;
      draft.clear();
      answers.clear();
    });
    try {
      Json d = await widget.api.call('/local/${Uri.encodeComponent(id)}');
      if (!mounted || token != generation) return;
      setState(() {
        detail = d;
        online = active;
      });
      if (widget.role != 'view' &&
          d['managed'] != true &&
          d['desktopLive'] != true &&
          d['archived'] != true) {
        d = await widget.api.call(
          '/local/${Uri.encodeComponent(d['id'])}/activate',
          {},
        );
      }
      if (mounted && token == generation) {
        setState(() => detail = d);
        bottom();
      }
    } catch (e) {
      if (mounted && token == generation) failure(e);
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  void bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
    }
  });
  Future<void> poll() async {
    if (polling || loading || busy || !active) return;
    polling = true;
    final token = generation;
    final current = detail;
    try {
      if (++ticks % 8 == 0) await load();
      if (current != null) {
        final d = await widget.api.call(
          '/local/${Uri.encodeComponent(current['id'])}',
        );
        if (mounted && token == generation) {
          final follow = scroll.hasClients && scroll.position.extentAfter < 100;
          setState(() {
            if (detail?['pending']?['id'] != d['pending']?['id']) {
              answers.clear();
            }
            detail = d;
            online = active;
            error = '';
          });
          if (follow) bottom();
        }
      }
    } catch (e) {
      if (token == generation) failure(e);
    } finally {
      polling = false;
    }
  }

  Future<void> control(String action, [Json extra = const {}]) async {
    final d = detail;
    if (d == null ||
        busy ||
        loading ||
        !active ||
        !canControl(d, widget.role, online)) {
      return;
    }
    final token = generation;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.api.call(controlPath(d), {
        'action': action,
        'requestId': requestId(),
        ...extra,
      });
      if (mounted && token == generation && action == 'send') draft.clear();
      final updated = await widget.api.call(
        '/local/${Uri.encodeComponent(d['id'])}',
      );
      if (mounted && token == generation) {
        setState(() => detail = updated);
        bottom();
      }
    } catch (e) {
      if (token == generation) failure(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> create() async {
    final title = TextEditingController(), prompt = TextEditingController();
    String selected = 'Hermes', cwd = '';
    final result = await collieSheet<Json>(
      context,
      '新建会话',
      (ctx) => StatefulBuilder(
        builder: (ctx, change) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            muted(ctx, '选择助手，开始一项新工作', size: 13),
            const SizedBox(height: 18),
            Row(
              children: [
                for (final value in ['Hermes', 'Codex'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton(
                        onPressed: () => change(() => selected = value),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: selected == value
                              ? panelColor(ctx)
                              : null,
                          padding: const EdgeInsets.all(14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Row(
                          children: [
                            agentLogo(value),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                value,
                                style: TextStyle(
                                  color: Theme.of(ctx).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (selected == value) glyph('Check', size: 17),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            muted(
              ctx,
              selected == 'Codex'
                  ? '在电脑 Codex 创建，并发送第一条消息。'
                  : '在电脑 Hermes 后端创建，首次发送后保存历史记录。',
            ),
            const SizedBox(height: 18),
            const Text('项目', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: cwd,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: '', child: Text('无项目 · 默认目录')),
                ...projects.map(
                  (p) => DropdownMenuItem<String>(
                    value: p['path'],
                    child: Text(
                      '${p['name']} · ${p['path']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (v) => change(() => cwd = v!),
            ),
            const SizedBox(height: 18),
            const Text('名称', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: title,
              maxLength: 100,
              onChanged: (_) => change(() {}),
              decoration: const InputDecoration(
                hintText: '想开展什么工作？',
                counterText: '',
              ),
            ),
            if (selected == 'Codex') ...[
              const SizedBox(height: 18),
              const Text('第一条消息', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: prompt,
                maxLength: 4000,
                maxLines: 3,
                onChanged: (_) => change(() {}),
                decoration: const InputDecoration(
                  hintText: '想让 Codex 做什么？',
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 22),
            OutlinedButton(
              onPressed:
                  title.text.trim().isEmpty ||
                      (selected == 'Codex' && prompt.text.trim().isEmpty)
                  ? null
                  : () => Navigator.pop(ctx, {
                      'agent': selected,
                      'title': title.text.trim(),
                      'prompt': selected == 'Codex' ? prompt.text : '',
                      'cwd': cwd,
                      'requestId': requestId(),
                    }),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('开始会话'),
                  const SizedBox(width: 12),
                  glyph('ArrowUp', size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // Controllers are released after the dialog's closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    title.dispose();
    prompt.dispose();
    if (result == null || !mounted) return;
    setState(() => busy = true);
    try {
      final d = await widget.api.call('/sessions', result);
      await load();
      if (mounted) await open(d['id']);
    } catch (e) {
      failure(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disconnect() async {
    try {
      await widget.api.call('/auth/logout', {});
    } catch (e) {
      failure(e);
      return;
    }
    await storage.delete(key: 'cookie:${widget.api.base}');
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    draft.dispose();
    for (final c in answerControllers.values) {
      c.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  Widget pendingPanel(Json p, bool enabled) {
    final params = (p['params'] as Map?) ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              p['kind'] == 'approval' ? '需要你的审批' : '需要你的回答',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (params['command'] != null)
              SelectableText('${params['command']}'),
            if (p['kind'] == 'approval')
              Wrap(
                spacing: 12,
                children: [
                  for (final choice in ['accept', 'decline'])
                    if (params['availableDecisions'] == null ||
                        (params['availableDecisions'] as List).isEmpty ||
                        (params['availableDecisions'] as List).contains(choice))
                      OutlinedButton(
                        onPressed: enabled
                            ? () => control('answer', {
                                'pendingId': p['id'],
                                'decision': choice,
                              })
                            : null,
                        child: Text(choice == 'accept' ? '批准一次' : '拒绝'),
                      ),
                ],
              ),
            if (p['kind'] == 'question') ...[
              for (final q in params['questions'] ?? []) ...[
                const SizedBox(height: 12),
                Text('${q['question'] ?? q['header'] ?? ''}'),
                if (q['options'] is List)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final o in q['options'])
                        ActionChip(
                          label: Text('${o['label']}'),
                          onPressed: enabled
                              ? () => setState(() {
                                  answers['${q['id']}'] = '${o['label']}';
                                  answerControllers['${p['id']}:${q['id']}']
                                          ?.text =
                                      '${o['label']}';
                                })
                              : null,
                        ),
                    ],
                  ),
                TextFormField(
                  key: ValueKey('${p['id']}:${q['id']}'),
                  controller: answerControllers.putIfAbsent(
                    '${p['id']}:${q['id']}',
                    () => TextEditingController(
                      text: answers['${q['id']}'] ?? '',
                    ),
                  ),
                  enabled: enabled,
                  maxLength: 4000,
                  onChanged: (v) => answers['${q['id']}'] = v,
                ),
              ],
              FilledButton(
                onPressed: enabled
                    ? () => control('answer', {
                        'pendingId': p['id'],
                        'answers': Map<String, String>.from(answers),
                      })
                    : null,
                child: const Text('提交回答'),
              ),
            ],
            if (!['approval', 'question'].contains(p['kind']))
              const Text('此请求请在电脑端处理'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final enabled =
        d != null &&
        !busy &&
        !loading &&
        active &&
        canControl(d, widget.role, online);
    void home() {
      setState(() {
        generation++;
        detail = null;
        loading = false;
        draft.clear();
        answers.clear();
      });
    }

    return PopScope(
      canPop: d == null && !busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy && d != null) home();
      },
      child: CollieShell(
        api: widget.api,
        initialTheme: appTheme.value,
        initialLarge: appLarge.value,
        role: widget.role,
        error: error,
        online: online,
        loading: loading,
        busy: busy,
        enabled: enabled,
        running: d != null && isActive(d),
        sessions: sessions,
        projects: projects,
        warnings: warnings,
        detail: d,
        draft: draft,
        scroll: scroll,
        pending: d?['pending'] is Map
            ? pendingPanel(Map<String, dynamic>.from(d!['pending']), enabled)
            : null,
        onRefresh: load,
        onOpen: open,
        onHome: home,
        onCreate: create,
        onDisconnect: disconnect,
        onSend: (ids) async {
          await control('send', {'text': draft.text, 'attachments': ids});
          return error.isEmpty;
        },
        onStop: () => control('stop', {'turnId': d?['turnId']}),
        onDraft: () => setState(() {}),
        onClearError: () => setState(() => error = ''),
        onTheme: (mode) {
          appTheme.value = mode;
          storage.write(key: 'theme', value: mode.name);
        },
        onFont: (large) {
          appLarge.value = large;
          storage.write(key: 'fontLarge', value: '$large');
        },
      ),
    );
  }
}
