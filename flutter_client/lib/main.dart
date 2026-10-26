import 'profile.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'computers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'ui.dart';
import 'native.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await restoreProfile();
  runApp(const CollieApp());
}

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
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: companionGreen,
            brightness: brightness,
            surface: dark ? const Color(0xff212121) : Colors.white,
          ).copyWith(
            primary: dark ? Colors.white : ink,
            onPrimary: dark ? ink : Colors.white,
            secondary: dark ? Colors.white : ink,
            surfaceTint: Colors.transparent,
          ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xff212121) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark ? Colors.white : ink,
          foregroundColor: dark ? ink : Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark ? Colors.white : ink,
        ),
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
  bool restoring = true;
  String? error;
  CollieApi? api;
  String? pendingSession;
  String? switchTarget;
  bool addingComputer = false;
  bool rePairing = false;
  bool workspaceOpen = false;
  final computers = ComputerStore(storage);
  @override
  void initState() {
    super.initState();
    NativeBridge.onNetworkReady = () {
      if (mounted && !workspaceOpen && address.text.isNotEmpty) {
        NativeBridge.onLink?.call(address.text);
      }
    };
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
    if (mounted) {
      setState(() {
        restoring = true;
        busy = true;
      });
    }
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
        final rows = await computers.read();
        final known = rows.where((c) => c['address'] == saved).firstOrNull;
        CollieApi? client;
        final savedCookie = await storage.read(key: 'cookie:$saved');
        if (savedCookie != null && savedCookie.isNotEmpty) {
          client = CollieApi(
            serverUri(saved),
            cookie: savedCookie,
            saveCookie: (c) => storage.write(key: 'cookie:$saved', value: c),
          );
          await enter(client, known?['role'] ?? 'view', offline: true);
          return;
        }
        try {
          client = await makeApi(
            saved,
            await storage.read(key: 'cookie:$saved') ?? '',
          );
          final result = await client.call('/auth/status');
          if (result['paired'] == true) {
            await enter(client, result['device']['role']);
            return;
          }
          client.close();
          error = '配对已失效，请在电脑端获取新的配对码。';
          rePairing = true;
        } catch (e) {
          final credential = await storage.read(key: 'cookie:$saved');
          if (e is! ApiException || e.status != 401) {
            if (credential != null && credential.isNotEmpty) {
              client ??=
                  api ??
                  CollieApi(
                    serverUri(saved),
                    cookie: credential,
                    saveCookie: (c) =>
                        storage.write(key: 'cookie:$saved', value: c),
                  );
              await enter(client, known?['role'] ?? 'view', offline: true);
              return;
            }
          }
          client?.close();
          rethrow;
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) {
      setState(() {
        busy = false;
        restoring = false;
      });
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
      if (mounted) {
        setState(() {
          busy = false;
          restoring = false;
        });
      }
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

  Future<CollieApi> preferRemote(CollieApi current) async {
    if (!['127.0.0.1', 'localhost', '::1'].contains(current.base.host)) {
      return current;
    }
    CollieApi? remote;
    try {
      final network = await current.call('/network');
      final target =
          network['embedded']?['address'] ?? network['tailscale']?['httpsURL'];
      if (target is! String || !NativeBridge.embedded(serverUri(target))) {
        return current;
      }
      final base = serverUri(target);
      remote = CollieApi(
        base,
        cookie: current.cookie,
        saveCookie: (c) => storage.write(key: 'cookie:$base', value: c),
      );
      await NativeBridge.connect(remote);
      final before = await current.call('/auth/status');
      final after = await remote.call('/auth/status');
      if (after['paired'] != true ||
          before['device']?['id'] != after['device']?['id']) {
        throw ApiException('远程电脑身份不匹配');
      }
      await storage.write(key: 'cookie:$base', value: remote.cookie);
      await storage.write(key: 'server', value: '$base');
      address.text = '$base';
      current.close();
      return remote;
    } catch (_) {
      remote?.close();
      return current;
    }
  }

  Future<void> enter(
    CollieApi client,
    String role, {
    bool offline = false,
  }) async {
    if (!mounted) return;
    if (!offline) client = await preferRemote(client);
    api = client;
    if (!mounted) {
      client.close();
      return;
    }
    await computers.remember(client.base, role);
    final stored = await computers.read();
    String? computerName = stored
        .where((c) => c['address'] == '${client.base}')
        .firstOrNull?['name'];
    if (!offline) {
      try {
        final network = await client.call('/network');
        computerName = network['computerName'] as String?;
        await computers.remember(client.base, role, name: computerName);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      restoring = false;
      addingComputer = false;
      rePairing = false;
    });
    if (!offline &&
        await profileStorage.read(key: 'profile-onboarding-done') == null &&
        mounted) {
      await editPreviewWorkspace(context, first: true);
      await profileStorage.write(key: 'profile-onboarding-done', value: 'yes');
    }
    if (!mounted) return;
    workspaceOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Workspace(
          api: client,
          role: role,
          initialSession: pendingSession,
          computerName: computerName,
          onManageComputers: manageComputers,
          onPairingInvalid: () {
            error = '配对已失效，请在电脑端获取新的配对码。';
            rePairing = true;
          },
        ),
      ),
    );
    workspaceOpen = false;
    pendingSession = null;
    client.close();
    final target = switchTarget;
    switchTarget = null;
    if (mounted && target != null) {
      if (target == '__add__') {
        setState(() {
          addingComputer = true;
          address.clear();
          code.clear();
          error = null;
        });
      } else {
        address.text = target;
        await storage.write(key: 'server', value: target);
        await restore();
      }
      return;
    }
    if (mounted) {
      setState(() {
        busy = false;
        code.clear();
      });
    }
  }

  Future<void> manageComputers() async {
    final rows = await computers.read();
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '电脑与连接',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭电脑管理',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Text(
                '切换不会停止其他电脑上的任务。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final row in rows)
                        ListTile(
                          leading: const Icon(Icons.computer_outlined),
                          title: Text(
                            row['name'] ?? Uri.parse(row['address']).host,
                          ),
                          subtitle: Text(
                            row['address'] == address.text ? '当前电脑' : '已配对',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: row['address'] == address.text
                              ? const Icon(Icons.check, size: 18)
                              : const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(ctx, row['address']),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (workspaceOpen && api != null)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, '__settings__'),
                  child: const Text('连接设置'),
                ),
              if (workspaceOpen)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, '__retry__'),
                  child: const Text('重试连接当前电脑'),
                ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, '__add__'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加电脑'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == '__settings__' && api != null) {
      final role =
          rows
              .where((row) => row['address'] == address.text)
              .firstOrNull?['role'] ??
          'view';
      await collieSheet<void>(
        context,
        '连接设置',
        (ctx) => SettingsBody(api: api!, role: role, title: '电脑与连接'),
      );
      return;
    }
    if (selected == '__retry__') {
      try {
        if (api != null) await NativeBridge.connect(api!);
      } catch (_) {}
      return;
    }
    if (selected == address.text && workspaceOpen) return;
    if (workspaceOpen) {
      switchTarget = selected;
      Navigator.pop(context);
    } else if (selected == '__add__') {
      setState(() {
        addingComputer = true;
        address.clear();
        code.clear();
        error = null;
      });
    } else {
      await storage.write(key: 'server', value: selected);
      await restore();
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
  Widget build(BuildContext context) => restoring
      ? const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'G-Collie',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 20),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        )
      : Scaffold(
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
                    manageComputers();
                  } else {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('内置远程连接'),
                        content: const SizedBox(
                          width: 400,
                          child: NetworkPane(),
                        ),
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
              padding: EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        addingComputer
                            ? '添加一台电脑'
                            : rePairing
                            ? '重新配对电脑'
                            : '连接你的第一台电脑',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      muted(
                        context,
                        '在要连接的电脑上打开 G-Collie，进入“手机与配对”，获取电脑地址和 6 位配对码。',
                        size: 13,
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: address,
                        enabled: !busy,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: '电脑地址',
                          hintText: '例如：http://100.x.x.x:4310',
                          helperText: '填写电脑端显示的完整地址',
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 18),
                      muted(context, '配对码', size: 13),
                      const SizedBox(height: 8),
                      TextField(
                        controller: code,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '6 位配对码',
                          filled: true,
                          fillColor: panelColor(context),
                        ),
                      ),
                      const SizedBox(height: 18),
                      muted(context, '本手机名称（选填）', size: 13),
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
                      if (addingComputer)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() => addingComputer = false);
                                  await restore();
                                },
                          child: const Text('取消并返回原电脑'),
                        ),
                      const SizedBox(height: 15),
                      FilledButton(
                        onPressed:
                            busy ||
                                address.text.trim().isEmpty ||
                                code.text.trim().length != 6
                            ? null
                            : pair,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: Text(busy ? '正在配对…' : '配对并连接'),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '配对成功后进入会话首页。以后打开 App 会自动连接上次使用的电脑。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.7,
                          color: Colors.grey,
                        ),
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
  final String? computerName;
  final VoidCallback? onManageComputers;
  final VoidCallback? onPairingInvalid;
  const Workspace({
    super.key,
    required this.api,
    required this.role,
    this.initialSession,
    this.computerName,
    this.onManageComputers,
    this.onPairingInvalid,
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
  late String effectiveRole = widget.role;
  late String? connectionName = widget.computerName;
  bool nameRequested = false;
  int generation = 0, ticks = 0;
  bool refreshingConnection = false;
  final Map<String, dynamic> cachedDetails = {};
  Future<void> cacheWrite = Future.value();
  String? lastCache;
  String get cacheKey => 'workspace-cache:${widget.api.base}';

  Future<void> restoreWorkspace() async {
    try {
      final raw = await storage.read(key: cacheKey);
      if (raw != null && mounted && sessions.isEmpty && !online) {
        final saved = jsonDecode(raw);
        cachedDetails.addAll(Map<String, dynamic>.from(saved['details'] ?? {}));
        setState(() {
          sessions = saved['sessions'] ?? [];
          projects = saved['projects'] ?? [];
        });
      }
    } catch (_) {}
  }

  Future<void> saveWorkspace() {
    if (leaving || !mounted) return Future.value();
    final snapshot = jsonEncode({
      'sessions': sessions,
      'projects': projects,
      'details': cachedDetails,
    });
    if (snapshot == lastCache) return cacheWrite;
    lastCache = snapshot;
    cacheWrite = cacheWrite
        .then((_) async {
          if (!leaving && mounted) {
            await storage.write(key: cacheKey, value: snapshot);
          }
        })
        .catchError((_) {
          lastCache = null;
        });
    return cacheWrite;
  }

  void rememberDetail(Json value) {
    cachedDetails[value['id']] = value;
    while (cachedDetails.length > 10) {
      cachedDetails.remove(cachedDetails.keys.first);
    }
    unawaited(saveWorkspace());
  }

  Timer? timer;
  final answers = <String, String>{};
  final answerControllers = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restoreWorkspace();
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
    }
    unawaited(
      widget.api
          .recordFailure('/connection/lifecycle', 'lifecycle-${state.name}')
          .catchError((_) {}),
    );
  }

  void leaveWorkspace() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    navigator.popUntil((candidate) => candidate == route || candidate.isFirst);
    if (route?.isCurrent == true && route?.isFirst == false) navigator.pop();
  }

  int connectionCheck = 0;

  void failure(Object e) {
    if (!mounted) return;
    if (e is ApiException && e.status == 401) {
      if (!leaving) {
        leaving = true;
        widget.onPairingInvalid?.call();
        unawaited(
          storage
              .delete(key: 'cookie:${widget.api.base}')
              .then((_) {
                if (mounted) leaveWorkspace();
              })
              .catchError((_) {
                if (mounted) leaveWorkspace();
              }),
        );
      }
      return;
    }
    if (leaving) return;
    if (e is ApiException && e.status >= 400) {
      setState(() => error = '$e');
      return;
    }
    setState(() => error = '$e');
    final check = ++connectionCheck;
    final token = generation;
    unawaited(
      widget.api.reachable().then((reachable) {
        if (!mounted ||
            leaving ||
            check != connectionCheck ||
            token != generation) {
          return;
        }
        setState(() {
          online = reachable;
          error = reachable ? '会话请求暂未完成，电脑连接正常；正在重试' : '电脑暂时不可达，正在重连';
        });
        unawaited(
          widget.api
              .recordFailure(
                '/connection/health',
                reachable ? 'reachable-after-request-error' : 'unreachable',
              )
              .catchError((_) {}),
        );
      }),
    );
  }

  Future<void> load() async {
    if (refreshingConnection || leaving) return;
    if (mounted) setState(() => refreshingConnection = true);
    try {
      if (!online && NativeBridge.embedded(widget.api.base)) {
        await NativeBridge.connect(widget.api);
      }
      if (!online) {
        final auth = await widget.api.call('/auth/status');
        if (auth['paired'] == false) throw ApiException('配对已失效，请重新配对', 401);
        if (auth['paired'] == true) {
          final role = auth['device']?['role'];
          effectiveRole = ['owner', 'control', 'view'].contains(role)
              ? role
              : 'view';
          await ComputerStore(
            storage,
          ).remember(widget.api.base, effectiveRole, select: false);
        }
      }
      final data = await widget.api.call('/local');
      if (mounted) {
        setState(() {
          sessions = data['sessions'] ?? [];
          projects = data['projects'] ?? [];
          warnings = data['warnings'] ?? [];
          connectionCheck++;
          online = true;
          error = '';
        });
      }
      if (!nameRequested) {
        nameRequested = true;
        unawaited(
          widget.api
              .call('/network')
              .then((network) async {
                final name = network['computerName'];
                if (name is String && name.trim().isNotEmpty) {
                  if (!mounted || leaving) return;
                  if (mounted) setState(() => connectionName = name);
                  await ComputerStore(storage).remember(
                    widget.api.base,
                    effectiveRole,
                    name: name,
                    select: false,
                  );
                }
              })
              .catchError((_) {}),
        );
      }
      unawaited(saveWorkspace());
    } catch (e) {
      failure(e);
    } finally {
      if (mounted) setState(() => refreshingConnection = false);
    }
  }

  Future<void> open(String id) async {
    if (id.startsWith('draft-agent:') && detail?['draft'] == true) {
      setState(() => detail = {...detail!, 'agent': id.substring(12)});
      return;
    }
    if (id.startsWith('draft-project:') && detail?['draft'] == true) {
      setState(() => detail = {...detail!, 'cwd': id.substring(14)});
      return;
    }
    final sameSession = detail?['id'] == id;
    final token = ++generation;
    connectionCheck++;
    setState(() {
      loading = true;
      error = '';
      if (!sameSession) {
        detail = null;
        draft.clear();
        answers.clear();
      }
    });
    try {
      Json d = await widget.api.call('/local/${Uri.encodeComponent(id)}');
      if (!mounted || token != generation) return;
      setState(() {
        detail = d;
        connectionCheck++;
        online = true;
      });
      if (effectiveRole != 'view' &&
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
        rememberDetail(d);
        if (!sameSession) bottom();
      }
    } catch (e) {
      if (mounted && token == generation) {
        final cached = cachedDetails[id];
        if (!sameSession && cached is Map) {
          setState(
            () => detail = {
              ...Map<String, dynamic>.from(cached),
              'readOnly': true,
              'desktopControl': false,
              'desktopLive': false,
              'status': 'unknown',
            },
          );
        }
        failure(e);
      }
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
      if (!online || ++ticks % 8 == 0) await load();
      if (current != null && current['draft'] != true) {
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
            connectionCheck++;
            online = true;
            error = '';
          });
          rememberDetail(d);
          if (follow) bottom();
        }
      }
    } catch (e) {
      if (token == generation) failure(e);
    } finally {
      polling = false;
    }
  }

  String? uncertainSendKey;
  String? uncertainSendId;
  Future<bool> control(String action, [Json extra = const {}]) async {
    final d = detail;
    if (d == null ||
        busy ||
        loading ||
        !active ||
        !canControl(d, effectiveRole, online)) {
      return false;
    }
    final token = generation;
    final fingerprint = jsonEncode({'session': d['id'], ...extra});
    final operationId = action == 'send' && uncertainSendKey == fingerprint
        ? uncertainSendId!
        : requestId();
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.api.call(controlPath(d), {
        'action': action,
        'requestId': operationId,
        ...extra,
      });
      if (mounted && token == generation) {
        setState(() {
          if (action == 'send') {
            draft.clear();
            uncertainSendKey = null;
            uncertainSendId = null;
          }
          busy = false;
        });
        // Sending is already acknowledged. A history read failure must not undo it.
        unawaited(() async {
          try {
            final updated = await widget.api.call(
              '/local/${Uri.encodeComponent(d['id'])}',
            );
            if (mounted && token == generation) {
              setState(() {
                detail = updated;
                error = '';
                online = true;
                connectionCheck++;
              });
              bottom();
              rememberDetail(updated);
            }
          } catch (e) {
            if (mounted && token == generation) {
              if (action == 'send') {
                setState(() => error = '消息已发送，记录同步暂未完成；正在重试，请勿重复发送');
              } else {
                failure(e);
              }
            }
          }
        }());
      }
      return true;
    } catch (e) {
      if (mounted && token == generation) {
        final uncertain =
            e is! ApiException ||
            e.status == 0 ||
            e.status >= 500 ||
            RegExp('结果未知|结果可能未知|已提交|超时').hasMatch('$e');
        if (action == 'send' && uncertain) {
          uncertainSendKey = fingerprint;
          uncertainSendId = operationId;
          setState(() => error = '发送结果待确认，正在同步电脑状态；请勿重复发送');
        } else {
          failure(e);
        }
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> create() async {
    final previous = detail;
    setState(() {
      generation++;
      loading = false;
      error = '';
      draft.clear();
      answers.clear();
      detail = {
        'id': 'draft:${requestId()}',
        'draft': true,
        'agent': previous?['agent'] ?? 'Hermes',
        'cwd': previous?['projectPath'] ?? '',
        'title': '新会话',
        'status': 'idle',
        'events': <Json>[],
      };
    });
  }

  Future<bool> sendDraft(List<String> ids) async {
    final d = detail!;
    if (busy || !online || (draft.text.trim().isEmpty && ids.isEmpty)) {
      return false;
    }
    final text = draft.text;
    final token = generation;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await widget.api.call('/sessions', {
        'agent': d['agent'],
        'cwd': d['cwd'],
        'prompt': text,
        'draftId': d['id'],
        'attachments': ids,
        'requestId': (d['id'] as String).substring(6),
      });
      if (mounted && token == generation) {
        await open(result['id']);
        await load();
      }
      return true;
    } catch (e) {
      // Keep the draft and its request id: an uncertain submission must not replay.
      if (mounted && token == generation) setState(() => error = '$e');
      return false;
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
    leaving = true;
    await cacheWrite;
    await ComputerStore(storage).forget(widget.api.base);
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
        (d['draft'] == true
            ? online && effectiveRole != 'view'
            : canControl(d, effectiveRole, online));
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
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          leaving = true;
          generation++;
        }
        if (!didPop && !busy && d != null) home();
      },
      child: CollieShell(
        api: widget.api,
        connecting: refreshingConnection && !online,
        computerName: connectionName,
        onManageComputers: widget.onManageComputers,
        initialTheme: appTheme.value,
        initialLarge: appLarge.value,
        role: effectiveRole,
        error: online ? error : '',
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
          if (detail?['draft'] == true) return sendDraft(ids);
          return control('send', {'text': draft.text, 'attachments': ids});
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
