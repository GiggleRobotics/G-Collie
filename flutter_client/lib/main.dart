import 'session_events.dart';
import 'pairing_link.dart';
import 'request_input.dart';
import 'offline_assets.dart';
import 'profile.dart';
import 'diagnostic_sync.dart';
import 'pending_messages.dart';
import 'dart:async';
import 'dart:convert';
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
const green = Color(0xff333333);

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
            errorContainer: dark
                ? const Color(0xff303030)
                : const Color(0xfff4f4f4),
            onErrorContainer: dark
                ? const Color(0xffffb4ab)
                : const Color(0xff93000a),
            onSecondary: dark ? ink : Colors.white,
            primaryContainer: dark
                ? const Color(0xff363636)
                : const Color(0xffeeeeee),
            onPrimaryContainer: dark ? Colors.white : ink,
            secondaryContainer: dark
                ? const Color(0xff363636)
                : const Color(0xffeeeeee),
            onSecondaryContainer: dark ? Colors.white : ink,
            tertiary: dark ? Colors.white : ink,
            onTertiary: dark ? ink : Colors.white,
            tertiaryContainer: dark
                ? const Color(0xff363636)
                : const Color(0xffeeeeee),
            onTertiaryContainer: dark ? Colors.white : ink,
            surfaceDim: dark
                ? const Color(0xff171717)
                : const Color(0xffdddddd),
            surfaceBright: dark ? const Color(0xff383838) : Colors.white,
            surfaceContainerLowest: dark
                ? const Color(0xff171717)
                : Colors.white,
            surfaceContainerLow: dark
                ? const Color(0xff242424)
                : const Color(0xfff9f9f9),
            surfaceContainer: dark
                ? const Color(0xff292929)
                : const Color(0xfff4f4f4),
            surfaceContainerHigh: dark
                ? const Color(0xff303030)
                : const Color(0xffeeeeee),
            surfaceContainerHighest: dark
                ? const Color(0xff363636)
                : const Color(0xffe7e7e7),
            onSurface: dark ? const Color(0xffeeeeee) : ink,
            onSurfaceVariant: dark
                ? const Color(0xffaaaaaa)
                : const Color(0xff666666),
            outline: dark ? const Color(0xff888888) : const Color(0xff777777),
            outlineVariant: dark
                ? const Color(0xff454545)
                : const Color(0xffdddddd),
          ),
      popupMenuTheme: PopupMenuThemeData(
        color: dark ? const Color(0xff292929) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            dark ? const Color(0xff292929) : Colors.white,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
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
  final pairingDraft = PairingLinkDraft();
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
      if (call.method == 'networkChanged') {
        NativeBridge.onNetworkChanged?.call();
      }
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
      final invite = parsePairingLink(value);
      if (invite != null) await pair(invite: invite);
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
              collieSheet<void>(context, '远程连接', (_) => NetworkPane(api: api));
            },
            child: const Text('远程连接'),
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
      final invite = parsePairingLink(normalized.toString());
      if (invite != null) {
        await pair(invite: invite);
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
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
                  child: const Text('连接状态'),
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
        '连接状态',
        (ctx) => SettingsBody(api: api!, role: role, title: '电脑与连接'),
      );
      return;
    }
    if (selected == '__add__') {
      final added = await collieSheet<String>(
        context,
        '添加电脑',
        (_) => AddComputerPane(computers: computers),
      );
      if (!mounted) return;
      if (added == null) {
        await manageComputers();
        return;
      }
      if (workspaceOpen) {
        switchTarget = added;
        Navigator.pop(context);
      } else {
        await storage.write(key: 'server', value: added);
        await restore();
      }
      return;
    }
    if (selected == address.text && workspaceOpen) return;
    if (workspaceOpen) {
      switchTarget = selected;
      Navigator.pop(context);
    } else if (selected == '__add__') {
      setState(() {
        addingComputer = true;
        pairingDraft.clear();
        address.clear();
        code.clear();
        error = null;
      });
    } else {
      await storage.write(key: 'server', value: selected);
      await restore();
    }
  }

  Future<void> pair({PairingInvite? invite}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final base = serverUri(invite?.address ?? address.text);
      final secret = invite?.code ?? pairingDraft.codeFor('$base', code.text);
      if (secret == null) throw const FormatException('请输入有效配对码或完整配对链接');
      final client = await makeApi('$base', '');
      final result = await client.call('/auth/pair', {
        'code': secret,
        'name': name.text.trim().isEmpty ? '我的手机' : name.text.trim(),
      });
      await storage.write(key: 'server', value: '$base');
      pairingDraft.clear();
      code.clear();
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
                    collieSheet<void>(
                      context,
                      '远程连接',
                      (_) => NetworkPane(api: api),
                    );
                  }
                },
                itemBuilder: (_) => [
                  '远程连接',
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
                        inputFormatters: [
                          PairingLinkFormatter(
                            address: address,
                            code: code,
                            draft: pairingDraft,
                            onInviteChanged: () => setState(() {}),
                          ),
                        ],
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
                          PairingLinkFormatter(
                            address: address,
                            code: code,
                            codeField: true,
                            draft: pairingDraft,
                            onInviteChanged: () => setState(() {}),
                          ),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: pairingDraft.hasInvite
                              ? '已读取配对链接'
                              : '6 位配对码',
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
                          child: const Text('取消'),
                        ),
                      const SizedBox(height: 15),
                      FilledButton(
                        onPressed:
                            busy ||
                                address.text.trim().isEmpty ||
                                pairingDraft.codeFor(address.text, code.text) ==
                                    null
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
  final Json? initialData;
  final String? computerName;
  final Future<void> Function()? onManageComputers;
  final VoidCallback? onPairingInvalid;
  const Workspace({
    super.key,
    required this.api,
    required this.role,
    this.initialSession,
    this.initialData,
    this.computerName,
    this.onManageComputers,
    this.onPairingInvalid,
  });
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  final draft = TextEditingController();
  final scroll = ScrollController(keepScrollOffset: false);
  bool followingLatest = true,
      positioningLatest = false,
      bottomScheduled = false;
  int bottomGeneration = 0;
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
  bool refreshingConnection = false, reconnecting = false;
  Future<void>? loadPending;
  final Map<String, dynamic> cachedDetails = {};
  Future<void> cacheWrite = Future.value();
  String? lastCache;
  final savedDrafts = <String, String>{};
  Timer? draftTimer;
  String get draftKey => 'workspace-drafts:${widget.api.base}';
  String draftId() => '${detail?['id'] ?? ''}';
  void persistDraft() {
    final id = draftId();
    if (id.isEmpty) return;
    if (draft.text.isEmpty) {
      savedDrafts.remove(id);
    } else {
      savedDrafts[id] = draft.text;
    }
    final snapshot = jsonEncode(savedDrafts);
    cacheWrite = cacheWrite
        .catchError((_) {})
        .then((_) => storage.write(key: draftKey, value: snapshot));
  }

  void draftChanged() {
    draftTimer?.cancel();
    draftTimer = Timer(const Duration(milliseconds: 300), persistDraft);
  }

  String get cacheKey => 'workspace-cache:${widget.api.base}';

  Future<void> restoreWorkspace() async {
    try {
      final raw = await storage.read(key: cacheKey);
      if (raw != null && mounted) {
        final saved = jsonDecode(raw);
        final older = Map<String, dynamic>.from(saved['details'] ?? {});
        for (final entry in older.entries) {
          cachedDetails.putIfAbsent(entry.key, () => entry.value);
        }
        if (sessions.isEmpty && !online) {
          setState(() {
            sessions = saved['sessions'] ?? [];
            projects = saved['projects'] ?? [];
          });
        }
      }
      final draftRaw = await storage.read(key: draftKey);
      if (draftRaw != null && mounted) {
        savedDrafts.addAll(Map<String, String>.from(jsonDecode(draftRaw)));
        if (draft.text.isEmpty) draft.text = savedDrafts[draftId()] ?? '';
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
    cachedDetails.remove(value['id']);
    cachedDetails[value['id']] = {
      ...value,
      'lastSyncedAt': DateTime.now().toIso8601String(),
    };
    while (cachedDetails.length > 25 ||
        (cachedDetails.length > 1 &&
            utf8.encode(jsonEncode(cachedDetails)).length > 3 * 1024 * 1024)) {
      cachedDetails.remove(cachedDetails.keys.first);
    }
    unawaited(saveWorkspace());
  }

  late final sessionEvents = SessionEvents(widget.api, queueEventRefresh, (
    error,
  ) {
    if (error is ApiException && error.status == 401) failure(error);
  });
  Timer? eventRefresh;
  void queueEventRefresh() {
    eventRefresh ??= Timer(const Duration(milliseconds: 150), () {
      eventRefresh = null;
      if (!mounted || !active || leaving) return;
      if (loading || polling) {
        queueEventRefresh();
        return;
      }
      unawaited(poll(fromEvent: true));
    });
  }

  Timer? networkRefresh;
  int networkRevision = 0;
  void networkChanged() {
    if (!mounted || leaving || !active) return;
    final revision = ++networkRevision;
    sessionEvents.stop();
    networkRefresh?.cancel();
    networkRefresh = Timer(const Duration(milliseconds: 300), () async {
      // Physical links change underneath the same tsnet node and loopback gateway.
      // Verify that gateway before paying for another native Open/health sequence.
      final check = connectionCheck;
      final reachable = await widget.api.reachable();
      if (!mounted || leaving || !active || revision != networkRevision) return;
      if (check != connectionCheck) {
        if (online) sessionEvents.start();
        return;
      }
      nextConnectionAttempt = DateTime.fromMillisecondsSinceEpoch(0);
      if (reachable) {
        setState(() {
          online = true;
          error = '';
        });
        sessionEvents.start();
        queueEventRefresh();
      } else {
        setState(() => online = false);
        await load();
        if (mounted && active && online) sessionEvents.start();
      }
    });
  }

  Timer? timer;
  final answers = <String, String>{};
  final answerControllers = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    draft.addListener(draftChanged);
    scroll.addListener(historyScroll);
    final seed = widget.initialData;
    if (seed != null) {
      sessions = seed['sessions'] ?? [];
      projects = seed['projects'] ?? [];
      detail = seed['detail'];
      online = seed['online'] == true;
    }
    NativeBridge.onNetworkChanged = networkChanged;
    final initialLoad = load();
    restoreWorkspace().then((_) async {
      // Connection state must be established before opening the initial chat.
      // Otherwise fast cache restoration can open an empty offline placeholder.
      await initialLoad;
      if (!mounted) return;
      if (widget.initialSession != null && seed == null) {
        open(widget.initialSession!);
      }
    });
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
      nextRoleCheck = DateTime.fromMillisecondsSinceEpoch(0);
      load();
      queueEventRefresh();
      sessionEvents.start();
    } else {
      sessionEvents.stop();
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
    if (e is ApiException && e.status == 403) {
      unawaited(
        refreshRole(force: true).catchError((Object error) {
          if (error is ApiException && error.status == 401) failure(error);
        }),
      );
    }
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

  Future<void> load() {
    if (leaving) return Future.value();
    return loadPending ??= loadCurrent().whenComplete(() => loadPending = null);
  }

  Future<void> reconnect() async {
    if (reconnecting || leaving || !mounted) return;
    setState(() => reconnecting = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在重新连接当前电脑…')));
    try {
      if (loadPending != null) await loadPending;
      if (!mounted || leaving) return;
      setState(() {
        online = false;
        error = '';
      });
      await load();
      if (online && detail != null && detail?['draft'] != true) {
        await open(detail!['id']);
      }
      if (mounted && !leaving) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(online ? '已重新连接当前电脑' : '未能连接电脑，请检查电脑服务与网络')),
        );
      }
    } finally {
      if (mounted) setState(() => reconnecting = false);
    }
  }

  DateTime nextConnectionAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime nextRoleCheck = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? roleCheck;
  Future<void> refreshRole({bool force = false}) {
    if (roleCheck != null) return roleCheck!;
    if (!force && DateTime.now().isBefore(nextRoleCheck)) return Future.value();
    // Bound both successful and failed checks; the existing index refresh polls
    // permissions without adding an authentication request to every chat tick.
    nextRoleCheck = DateTime.now().add(const Duration(seconds: 15));
    return roleCheck = readRole().whenComplete(() => roleCheck = null);
  }

  Future<void> readRole() async {
    final auth = await widget.api.call('/auth/status');
    if (!mounted || leaving) return;
    if (auth['paired'] == false) throw ApiException('配对已失效，请重新配对', 401);
    if (auth['paired'] == true) {
      final role = auth['device']?['role'];
      setState(
        () => effectiveRole = ['owner', 'control', 'view'].contains(role)
            ? role
            : 'view',
      );
      // Persist metadata independently: secure storage must not hold up the
      // permission change or prevent a live session from loading.
      unawaited(
        ComputerStore(storage)
            .remember(widget.api.base, effectiveRole, select: false)
            .catchError((_) {}),
      );
    }
  }

  Future<void> loadCurrent() async {
    if (leaving) return;
    if (mounted) setState(() => refreshingConnection = true);
    var rebuiltConnection = false;
    try {
      if (!online && NativeBridge.embedded(widget.api.base)) {
        await NativeBridge.connect(widget.api);
        rebuiltConnection = true;
      }
      await refreshRole();
      if (!mounted || leaving) return;
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
      if (mounted && active && online) sessionEvents.start();
      if (rebuiltConnection &&
          await NativeBridge.invoke<bool>('notificationEnabled') == true) {
        unawaited(
          NativeBridge.startNotifications(widget.api).catchError((_) {}),
        );
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
      if (!online) {
        nextConnectionAttempt = DateTime.now().add(const Duration(seconds: 10));
      }
      if (mounted) setState(() => refreshingConnection = false);
    }
  }

  Json localDetail(String id, Map cached) => {
    ...Map<String, dynamic>.from(cached),
    'id': id,
    'readOnly': true,
    'desktopControl': false,
    'desktopLive': false,
    'status': 'unknown',
    'pending': null,
    'localHistory': true,
  };

  String? retryOpenId;

  Future<void> open(String id) async {
    retryOpenId = null;
    if (id.startsWith('draft-agent:') && detail?['draft'] == true) {
      if (busy ||
          uncertainDrafts.containsKey(detail?['id']) ||
          effectiveRole == 'view') {
        return;
      }
      setState(() => detail = {...detail!, 'agent': id.substring(12)});
      return;
    }
    if (id.startsWith('draft-project:') && detail?['draft'] == true) {
      if (busy ||
          uncertainDrafts.containsKey(detail?['id']) ||
          effectiveRole == 'view') {
        return;
      }
      setState(() => detail = {...detail!, 'cwd': id.substring(14)});
      return;
    }
    persistDraft();
    final sameSession = detail?['id'] == id;
    if (!sameSession) {
      followingLatest = true;
      positioningLatest = true;
      bottomGeneration++;
      bottomScheduled = false;
    }
    final token = ++generation;
    connectionCheck++;
    setState(() {
      loading = true;
      error = '';
      if (!sameSession) {
        final cached = cachedDetails[id];
        detail = cached is Map
            ? localDetail(id, cached)
            : detail?['draft'] == true
            ? mergeHistory(localDetail(id, {...detail!, 'draft': false}))
            : null;
        draft.text = savedDrafts[id] ?? '';
        answers.clear();
      }
    });
    if (!sameSession) bottom();
    if (!online) {
      setState(() {
        detail ??= {
          'id': id,
          'title': '会话历史',
          'agent': id.startsWith('codex:')
              ? 'Codex'
              : id.startsWith('hermes:')
              ? 'Hermes'
              : 'Claude Code',
          'events': <Json>[],
          'readOnly': true,
          'localHistory': true,
          'uncached': true,
          'status': 'unknown',
        };
        loading = false;
      });
      return;
    }
    var detailReadCompleted = false;
    try {
      Json d = await widget.api.call('/local/${Uri.encodeComponent(id)}');
      detailReadCompleted = true;
      if (!mounted || token != generation) return;
      setState(() {
        detail = mergeHistory(d);
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
        setState(() => detail = mergeHistory(d));
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
              'pending': null,
              'localHistory': true,
            },
          );
        }
        if (!detailReadCompleted &&
            (e is! ApiException || e.status == 0 || e.status >= 500)) {
          retryOpenId = id;
        }
        failure(e);
      }
    } finally {
      if (mounted && token == generation) {
        setState(() => loading = false);
        if (!sameSession && followingLatest) bottom();
      }
    }
  }

  final Map<String, List<dynamic>> olderHistory = {};
  final Map<String, String?> historyCursors = {};
  bool historyLoading = false;
  Json mergeHistory(Json incoming) {
    final id = incoming['id'] as String;
    final older = olderHistory[id] ?? [];
    if (!historyCursors.containsKey(id) &&
        incoming.containsKey('historyCursor')) {
      historyCursors[id] = incoming['historyCursor'] as String?;
    }
    final events = <String, dynamic>{};
    for (final e in [...older, ...incoming['events'] as List? ?? []]) {
      events['${e['id']}'] = e;
    }
    olderHistory[id] = events.values
        .where((e) => e['sendStatus'] == null)
        .toList();
    return pendingMessages.merge(
      {...incoming, 'events': events.values.toList()},
      onAcknowledged: (request, text) =>
          consumeSubmittedDraft(id, text, request),
    );
  }

  void historyScroll() {
    if (scroll.hasClients && scroll.position.extentAfter < 1) {
      followingLatest = true;
    }
    if (!positioningLatest &&
        scroll.hasClients &&
        scroll.position.pixels < 120) {
      unawaited(loadOlderHistory());
    }
  }

  Future<void> loadOlderHistory() async {
    final d = detail;
    if (d == null || !online || loading || historyLoading || !active) return;
    final id = d['id'] as String;
    final cursor = historyCursors[id];
    if (cursor == null) return;
    historyLoading = true;
    final token = generation;
    final extent = scroll.hasClients ? scroll.position.maxScrollExtent : 0.0;
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    try {
      final page = await widget.api.call(
        '/local/${Uri.encodeComponent(id)}/history?before=${Uri.encodeQueryComponent(cursor)}',
      );
      if (!mounted || token != generation || detail?['id'] != id) return;
      olderHistory[id] = [
        ...page['events'] as List? ?? [],
        ...olderHistory[id] ?? [],
      ];
      historyCursors[id] = page['historyCursor'] as String?;
      setState(() => detail = mergeHistory(detail!));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && token == generation && scroll.hasClients) {
          scroll.jumpTo(
            (offset + scroll.position.maxScrollExtent - extent).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    } catch (e) {
      if (mounted && token == generation) setState(() => error = '加载更早记录失败：$e');
    } finally {
      historyLoading = false;
    }
  }

  void conversationUserScroll() {
    followingLatest = false;
    positioningLatest = false;
    bottomGeneration++;
  }

  void conversationMetricsChanged() {
    if (followingLatest) bottom();
  }

  // Lazy lists first expose an estimated extent. Settle the actual end across
  // layouts, and follow later media-size changes only until the user scrolls.
  void bottom() {
    if (bottomScheduled) return;
    bottomScheduled = true;
    final token = generation;
    final request = bottomGeneration;
    var frames = 0, stable = 0;
    double? lastExtent;
    void settle(Duration _) {
      bottomScheduled = false;
      if (!mounted ||
          token != generation ||
          request != bottomGeneration ||
          !followingLatest ||
          !scroll.hasClients) {
        return;
      }
      final position = scroll.position;
      final extent = position.maxScrollExtent;
      stable = lastExtent == extent && position.extentAfter < 1
          ? stable + 1
          : 0;
      lastExtent = extent;
      position.jumpTo(extent);
      if (++frames < 24 && stable < 2) {
        bottomScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback(settle);
        WidgetsBinding.instance.scheduleFrame();
      } else {
        positioningLatest = false;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(settle);
  }

  final composerUploads = <Json>[];
  // Bind each selection to its submission, including when a skill is removed
  // and added again with the same server ID before a late receipt arrives.
  final uploadRequest = Expando<String>();

  void markSubmittedUploads(String request, List<String> ids) {
    for (final upload in composerUploads) {
      if (ids.contains(upload['id'])) uploadRequest[upload] = request;
    }
  }

  void consumeSubmittedDraft(String session, String submitted, String request) {
    composerUploads.removeWhere((upload) => uploadRequest[upload] == request);
    // Consume only the submitted snapshot, including its persisted draft.
    // A delayed receipt must never erase text written after that submission.
    if (detail?['id'] == session && draft.text == submitted) {
      draftTimer?.cancel();
      draft.clear();
      persistDraft();
    } else if (savedDrafts[session] == submitted) {
      savedDrafts.remove(session);
      final snapshot = jsonEncode(savedDrafts);
      cacheWrite = cacheWrite
          .catchError((_) {})
          .then((_) => storage.write(key: draftKey, value: snapshot));
    }
  }

  final uncertainDrafts = <String, ({String text, List<String> attachments})>{};

  Future<void> acknowledgeDraft(
    String session,
    String text,
    List<String> ids,
    Json receipt,
    int token,
  ) async {
    final id = receipt['id'] as String;
    uncertainDrafts.remove(session);
    for (final attachment in ids) {
      final preview = widget.api.attachmentPreviews[attachment];
      if (preview != null && preview['session'] == session) {
        preview['session'] = id;
      }
    }
    pendingMessages.move(session, id);
    pendingMessages.update(
      id,
      session.substring(6),
      'sent',
      turnId: receipt['turnId'] as String?,
    );
    if (!mounted) return;
    consumeSubmittedDraft(session, text, session.substring(6));
    if (token != generation) return;
    final remainingDraft = draft.text;
    await open(id);
    if (mounted && detail?['id'] == id && remainingDraft != text) {
      draft.text = remainingDraft;
      persistDraft();
    }
    await load();
  }

  void rejectDraft(
    String session,
    String request,
    String? message,
    Object? code,
    Object? attachmentId,
  ) {
    final reason = message?.trim() ?? '';
    // Legacy bridge errors may contain local paths, subprocess arguments or stderr.
    final technical =
        reason.length > 160 ||
        RegExp(
          r'[\r\n/\\]|ffmpeg|command failed',
          caseSensitive: false,
        ).hasMatch(reason);
    pendingMessages.failFirstSend(
      session,
      request,
      reason.isEmpty || technical ? '请检查附件或电脑服务后重试。' : reason,
      invalidImage:
          code == 'session_create_invalid_image' && attachmentId is String
          ? attachmentId
          : null,
    );
  }

  Future<void> reconcileDraft(String session, int token) async {
    final pending = uncertainDrafts[session];
    if (pending == null) return;
    final request = session.substring(6);
    final dynamic reply;
    try {
      reply = await widget.api.call('/sessions/requests/$request');
    } on ApiException catch (e) {
      if (mounted && token == generation && e.status == 401) failure(e);
      return;
    } catch (_) {
      // Older servers and interrupted reads leave the write outcome unknown.
      return;
    }
    if (!mounted || !active || reply is! Map) return;
    if (reply['state'] == 'done' && reply['result'] is Map) {
      final receipt = Map<String, dynamic>.from(reply['result']);
      if (receipt['id'] is String && (receipt['id'] as String).isNotEmpty) {
        await acknowledgeDraft(
          session,
          pending.text,
          pending.attachments,
          receipt,
          token,
        );
      }
    } else if (reply['state'] == 'failed') {
      uncertainDrafts.remove(session);
      rejectDraft(
        session,
        request,
        reply['error'] is String ? reply['error'] : null,
        reply['code'],
        reply['attachmentId'],
      );
      if (token == generation) {
        setState(() {
          detail = mergeHistory(detail!);
        });
      }
    }
  }

  late final diagnosticSync = DiagnosticSync(widget.api);
  Future<void> poll({bool fromEvent = false}) async {
    if (polling || loading || (!fromEvent && busy) || !active) return;
    polling = true;
    if (online) unawaited(diagnosticSync.tick());
    final token = generation;
    final current = detail;
    try {
      if (!online) {
        if (DateTime.now().isBefore(nextConnectionAttempt)) return;
        await load();
        if (!online) return;
      } else if (++ticks % 8 == 0) {
        await load();
      }
      if (retryOpenId != null) {
        await open(retryOpenId!);
        return;
      }
      if (current?['draft'] == true && token == generation && !busy) {
        await reconcileDraft(current!['id'], token);
      }
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
            detail = mergeHistory(d);
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

  final pendingMessages = PendingMessages();
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
    final session = d['id'] as String;
    final text = '${extra['text'] ?? ''}';
    final attachments = List<String>.from(extra['attachments'] ?? []);
    final retryId = action == 'send'
        ? pendingMessages.unknownRequest(session, text, attachments)
        : null;
    final operationId = retryId ?? requestId();
    if (action == 'send') {
      markSubmittedUploads(operationId, attachments);
      pendingMessages.add(
        session,
        operationId,
        text,
        d['events'] ?? [],
        attachments: attachments.isNotEmpty,
        attachmentIds: attachments,
        media: [
          for (final id in attachments)
            if (widget.api.attachmentPreviews[id]?['session'] == d['id'])
              'gcollie-upload:$id',
        ],
      );
    }
    setState(() {
      busy = true;
      error = '';
      if (action == 'send') detail = mergeHistory(d);
    });
    if (action == 'send') {
      followingLatest = true;
      bottom();
    }
    try {
      final receipt = await widget.api.call(controlPath(d), {
        'action': action,
        'requestId': operationId,
        ...extra,
      });
      if (action == 'send') {
        final alreadyConfirmed = pendingMessages.isAcknowledged(
          session,
          operationId,
        );
        pendingMessages.update(
          session,
          operationId,
          'sent',
          turnId: receipt is Map ? receipt['turnId'] as String? : null,
        );
        if (mounted && !alreadyConfirmed) {
          consumeSubmittedDraft(session, text, operationId);
        }
      }
      if (mounted && token == generation) {
        setState(() {
          if (action == 'send') {
            detail = mergeHistory(detail!);
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
                detail = mergeHistory(updated);
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
      // History may confirm the write while its HTTP response is still in flight.
      if (action == 'send' &&
          pendingMessages.isAcknowledged(session, operationId)) {
        return true;
      }
      final uncertain = operationResultUnknown(e);
      if (action == 'send') {
        pendingMessages.update(
          session,
          operationId,
          uncertain || retryId != null ? 'unknown' : 'failed',
        );
      }
      if (mounted && token == generation) {
        if (action == 'send') setState(() => detail = mergeHistory(detail!));
        if (action == 'send' && uncertain) {
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
    persistDraft();
    followingLatest = true;
    positioningLatest = false;
    bottomGeneration++;
    bottomScheduled = false;
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
    final d = detail;
    if (d == null ||
        d['draft'] != true ||
        busy ||
        loading ||
        !active ||
        !online ||
        effectiveRole == 'view' ||
        uncertainDrafts.containsKey(d['id']) ||
        ids.contains(
          pendingMessages.sessions[d['id']]?.lastOrNull?['invalidImage'],
        ) ||
        (draft.text.trim().isEmpty && ids.isEmpty)) {
      return false;
    }
    final text = draft.text;
    final token = generation;
    final session = d['id'] as String;
    final operationId = session.substring(6);
    markSubmittedUploads(operationId, ids);
    pendingMessages.add(
      d['id'],
      operationId,
      text,
      [],
      attachments: ids.isNotEmpty,
      attachmentIds: ids,
      media: [
        for (final id in ids)
          if (widget.api.attachmentPreviews[id]?['session'] == d['id'])
            'gcollie-upload:$id',
      ],
    );
    setState(() {
      busy = true;
      error = '';
      detail = mergeHistory(d);
    });
    bottom();
    try {
      final Json receipt;
      try {
        final result = await widget.api.call('/sessions', {
          'agent': d['agent'],
          'cwd': d['cwd'],
          'prompt': text,
          'draftId': session,
          'attachments': ids,
          'requestId': operationId,
        });
        if (result is! Map ||
            result['id'] is! String ||
            (result['id'] as String).isEmpty) {
          throw ApiException('电脑返回了无效响应，请检查服务地址');
        }
        receipt = Map<String, dynamic>.from(result);
      } catch (e) {
        final failed =
            e is ApiException &&
            (e.outcome == 'failed' || e.status == 401 || e.status == 403);
        if (failed) {
          rejectDraft(session, operationId, e.message, e.code, e.attachmentId);
        } else {
          uncertainDrafts[session] = (text: text, attachments: List.of(ids));
          pendingMessages.update(session, operationId, 'unknown');
        }
        if (mounted && token == generation) {
          setState(() => detail = mergeHistory(detail!));
          if (e is ApiException && (e.status == 401 || e.status == 403)) {
            failure(e);
          }
        }
        return false;
      }
      await acknowledgeDraft(session, text, ids, receipt, token);
      return true;
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
    sessionEvents.stop();
    eventRefresh?.cancel();
    networkRefresh?.cancel();
    networkRevision++;
    NativeBridge.onNetworkChanged = null;
    draftTimer?.cancel();
    persistDraft();
    draft.removeListener(draftChanged);
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
    if (['secret', 'question', 'approval'].contains(p['kind'])) {
      return RequestInputCard(
        key: ValueKey(
          'input-request:${p['id']}:${p['generation'] ?? 'legacy'}:${p['requestEpoch'] ?? 'legacy'}',
        ),
        request: p,
        enabled: enabled,
        onSubmit: (answer) => control('answer', {
          'pendingId': p['id'],
          if (p['generation'] != null) 'expectedGeneration': p['generation'],
          if (p['requestEpoch'] != null) 'requestEpoch': p['requestEpoch'],
          ...answer,
        }),
      );
    }
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('此请求类型尚未适配手机操作，可在电脑查看具体要求。'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final attachmentEnabled =
        d != null &&
        (d['draft'] == true
            ? online &&
                  effectiveRole != 'view' &&
                  !uncertainDrafts.containsKey(d['id'])
            : canControl(d, effectiveRole, online));
    final enabled = attachmentEnabled && !busy && !loading && active;
    void home() {
      persistDraft();
      draftTimer?.cancel();
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
        uploads: composerUploads,
        connecting: reconnecting || (refreshingConnection && !online),
        reconnecting: reconnecting,
        onReconnect: reconnect,
        computerName: connectionName,
        onClearCache: () async {
          await cacheWrite;
          cachedDetails.clear();
          lastCache = null;
          await storage.delete(key: cacheKey);
          await OfflineAssets.clear(computer: '${widget.api.base}');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已清理当前电脑的本地历史与图片，草稿已保留')),
            );
          }
        },
        onManageComputers: widget.onManageComputers,
        onDeleted: (ids) async {
          generation++;
          draftTimer?.cancel();
          for (final id in ids) {
            cachedDetails.remove(id);
            savedDrafts.remove(id);
            pendingMessages.sessions.remove(id);
            pendingMessages.matched.remove(id);
            pendingMessages.acknowledged.remove(id);
          }
          setState(() {
            sessions.removeWhere((s) => ids.contains(s['id']));
            if (ids.contains(detail?['id'])) {
              detail = null;
              draft.clear();
              answers.clear();
            }
            loading = false;
          });
          final snapshot = jsonEncode(savedDrafts);
          cacheWrite = cacheWrite
              .catchError((_) {})
              .then((_) => storage.write(key: draftKey, value: snapshot));
          await saveWorkspace();
          await load();
        },
        initialTheme: appTheme.value,
        initialLarge: appLarge.value,
        role: effectiveRole,
        error: online ? error : '',
        online: online,
        loading: loading,
        busy: busy,
        enabled: enabled,
        attachmentEnabled: attachmentEnabled,
        running: d != null && isActive(d),
        sessions: sessions,
        projects: projects,
        warnings: warnings,
        detail: d,
        draft: draft,
        scroll: scroll,
        onConversationMetrics: conversationMetricsChanged,
        onConversationUserScroll: conversationUserScroll,
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
