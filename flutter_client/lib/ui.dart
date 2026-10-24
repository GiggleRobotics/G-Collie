import 'reset_credits.dart';
import 'quota_notice.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'project_picker.dart';
import 'native.dart';
import 'resources.dart';
import 'process_record.dart';

const ink = Color(0xff171717);
const companionGreen = Color(0xff315c49);
Color panelColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xff303030)
    : const Color(0xfff4f4f4);
Color sidebarColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xff171717)
    : const Color(0xfff9f9f9);
Color mutedColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xff999999)
    : const Color(0xff888888);
Widget glyph(String name, {double size = 22, Color? color}) => Builder(
  builder: (c) => SvgPicture.asset(
    'assets/ui/$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      color ?? IconTheme.of(c).color ?? Theme.of(c).colorScheme.onSurface,
      BlendMode.srcIn,
    ),
  ),
);
Widget agentLogo(String agent, {double size = 22}) => agent == 'Claude Code'
    ? Icon(Icons.auto_awesome, size: size, color: const Color(0xffd97757))
    : agent == 'Codex'
    ? SvgPicture.asset('assets/codex.svg', width: size, height: size)
    : Image.asset('assets/hermes.png', width: size, height: size);
Widget collieMark({double size = 30}) => Image.asset(
  'assets/collie-mark-v2.png',
  width: size,
  height: size + 4,
  fit: BoxFit.contain,
);
Widget iconAction(
  String icon,
  String label,
  VoidCallback? onTap, {
  double size = 22,
}) => IconButton(
  tooltip: label,
  onPressed: onTap,
  icon: glyph(icon, size: size),
  style: IconButton.styleFrom(
    minimumSize: const Size(36, 36),
    padding: const EdgeInsets.all(7),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ),
);
Widget muted(BuildContext c, String value, {double size = 12}) => Text(
  value,
  style: TextStyle(fontSize: size, color: mutedColor(c), height: 1.7),
);
Widget outlineAction(String text, VoidCallback? action) => OutlinedButton(
  onPressed: action,
  style: OutlinedButton.styleFrom(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    foregroundColor: ink,
    side: const BorderSide(color: Color(0xffdddddd)),
  ),
  child: Text(text),
);
Future<T?> collieSheet<T>(
  BuildContext context,
  String title,
  Widget Function(BuildContext) content,
) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (ctx) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      28 + MediaQuery.viewInsetsOf(ctx).bottom,
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .82,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                iconAction('X', '关闭$title', () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 18),
            content(ctx),
          ],
        ),
      ),
    ),
  ),
);

class CollieShell extends StatefulWidget {
  final CollieApi api;
  final ThemeMode initialTheme;
  final bool initialLarge;
  final String role, error;
  final String? computerName;
  final VoidCallback? onManageComputers;
  final bool connecting;
  final bool online, loading, busy, enabled, running;
  final List<dynamic> sessions, projects, warnings;
  final Json? detail;
  final TextEditingController draft;
  final ScrollController scroll;
  final Widget? pending;
  final Future<void> Function() onRefresh;
  final void Function(String) onOpen;
  final VoidCallback onHome,
      onCreate,
      onDisconnect,
      onStop,
      onDraft,
      onClearError;
  final Future<bool> Function(List<String>) onSend;
  final void Function(ThemeMode) onTheme;
  final void Function(bool) onFont;
  const CollieShell({
    super.key,
    required this.api,
    this.computerName,
    this.onManageComputers,
    this.connecting = false,
    this.initialTheme = ThemeMode.system,
    this.initialLarge = false,
    required this.role,
    required this.error,
    required this.online,
    required this.loading,
    required this.busy,
    required this.enabled,
    required this.running,
    required this.sessions,
    required this.projects,
    required this.warnings,
    required this.detail,
    required this.draft,
    required this.scroll,
    this.pending,
    required this.onRefresh,
    required this.onOpen,
    required this.onHome,
    required this.onCreate,
    required this.onDisconnect,
    required this.onSend,
    required this.onStop,
    required this.onDraft,
    required this.onClearError,
    required this.onTheme,
    required this.onFont,
  });
  @override
  State<CollieShell> createState() => _CollieShellState();
}

class _CollieShellState extends State<CollieShell> {
  bool quotaBlocked = false;
  final Map<String, SessionResources> _resourceSessions = {};
  SessionResources get resources {
    final id = widget.detail?['id'] as String? ?? '';
    return _resourceSessions.putIfAbsent(
      id,
      () => SessionResources(widget.api, id),
    );
  }

  Widget eventBody(Json e) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if ('${e['text'] ?? ''}'.isNotEmpty) markdown('${e['text']}'),
      for (final ref in e['media'] ?? [])
        SessionImage(
          key: ValueKey('${widget.detail?['id']}:$ref'),
          resources: resources,
          source: '$ref',
        ),
    ],
  );
  final scaffold = GlobalKey<ScaffoldState>();
  String query = '', agent = 'all', project = '', page = 'chat';
  bool large = false, uploading = false;
  final uploads = <Json>[];
  String uploadError = '';
  String uploadStatus = '';
  @override
  void initState() {
    super.initState();
    mode = widget.initialTheme;
    large = widget.initialLarge;
  }

  @override
  void didUpdateWidget(covariant CollieShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail?['id'] != widget.detail?['id']) {
      uploads.clear();
      uploadError = '';
    }
  }

  Future<void> upload(String kind) async {
    final image = kind == 'image';
    final video = kind == 'video';
    if (uploading || !widget.enabled) return;
    final id = widget.detail?['id'];
    try {
      final files = await openFiles(
        acceptedTypeGroups: image
            ? [
                const XTypeGroup(
                  label: '照片',
                  extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
                ),
              ]
            : video
            ? [
                const XTypeGroup(
                  label: '视频',
                  extensions: ['mp4', 'mov', 'm4v', 'webm'],
                ),
              ]
            : [],
      );
      if (files.length + uploads.length > 5) {
        throw ApiException('每条消息最多添加 5 个附件');
      }
      if (files.isEmpty) return;
      setState(() {
        uploading = true;
        uploadStatus = '正在上传附件…';
      });
      for (final f in files) {
        final length = await f.length();
        if (length == 0 || length > (video ? 100 : 10) * 1024 * 1024) {
          throw ApiException(
            video ? '请选择不超过 100 MB 的视频' : '请选择不超过 10 MB 的非空文件',
          );
        }
        final value = video
            ? await widget.api.uploadVideo(
                id as String,
                f.name,
                length,
                f.openRead(),
                onProgress: (sent, total) {
                  if (mounted) {
                    setState(
                      () => uploadStatus = sent >= total
                          ? '正在完成视频上传…'
                          : '正在上传视频 ${(sent * 100 / total).floor()}%',
                    );
                  }
                },
              )
            : await widget.api.call('/attachments', {
                'session': id,
                'name': f.name,
                'image': image,
                'data': base64Encode(await f.readAsBytes()),
              });
        if (!mounted || widget.detail?['id'] != id) return;
        setState(() => uploads.add(Map<String, dynamic>.from(value)));
      }
    } catch (e) {
      if (mounted) setState(() => uploadError = '$e');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  ThemeMode mode = ThemeMode.system;
  Future<void> create() async {
    final settings = await chooseSessionSettings();
    if (settings == null || !mounted) return;
    setState(() => page = 'chat');
    widget.onCreate();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && widget.detail?['draft'] == true) {
      widget.onOpen('draft-agent:${settings['agent']}');
      widget.onOpen('draft-project:${settings['cwd']}');
    }
  }

  void open(String id) {
    setState(() => page = 'chat');
    widget.onOpen(id);
  }

  void nav(String value) {
    Navigator.pop(context);
    setState(() => page = value);
  }

  void home() {
    setState(() => page = 'chat');
    widget.onHome();
  }

  String group(dynamic s) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final dt = DateTime.fromMillisecondsSinceEpoch(
      (s['updatedAt'] as num? ?? 0).toInt(),
    );
    final days = start.difference(dt).inDays;
    return dt.isAfter(start)
        ? '今天'
        : days < 1
        ? '昨天'
        : days < 7
        ? '过去 7 天'
        : days < 30
        ? '过去 30 天'
        : '更早';
  }

  List<dynamic> get filtered => widget.sessions
      .where(
        (s) =>
            (agent == 'all' || s['agent'] == agent) &&
            (project.isEmpty ||
                s['projectPath'] == project ||
                s['cwd'] == project) &&
            '${s['title']} ${s['cwd']} ${s['model'] ?? ''}'
                .toLowerCase()
                .contains(query.toLowerCase()),
      )
      .toList();
  Widget navRow(
    String icon,
    String text,
    VoidCallback action, {
    String? trailing,
  }) => TextButton(
    onPressed: action,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      alignment: Alignment.centerLeft,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    ),
    child: Row(
      children: [
        glyph(icon, size: 19),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        if (trailing != null) muted(context, trailing, size: 11),
      ],
    ),
  );
  Widget drawer() {
    final rows = filtered;
    final groups = rows.map(group).toSet();
    return Drawer(
      width: (MediaQuery.sizeOf(context).width * .86).clamp(280, 320),
      backgroundColor: sidebarColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          child: Column(
            children: [
              Row(
                children: [
                  iconAction(
                    'PanelLeft',
                    '关闭侧边栏',
                    () => Navigator.pop(context),
                  ),
                  collieMark(size: 27),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'G-Collie',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  iconAction(
                    'SquarePen',
                    '新建会话',
                    widget.role == 'view' || widget.busy
                        ? null
                        : () {
                            Navigator.pop(context);
                            create();
                          },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: panelColor(context),
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    glyph('Search', size: 18, color: mutedColor(context)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => query = v),
                        decoration: const InputDecoration(
                          hintText: '搜索会话',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 11),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              navRow('MessageCircle', '会话首页', () {
                Navigator.pop(context);
                home();
              }),
              navRow(
                'Folder',
                '项目',
                () => nav('projects'),
                trailing: '${widget.projects.length}',
              ),
              navRow('Activity', '用量统计', () => nav('usage')),
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(width: 10),
                  Expanded(child: muted(context, '最近会话')),
                  iconAction('SlidersHorizontal', '筛选会话', filters, size: 16),
                ],
              ),
              if (agent != 'all' || project.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffe7f0eb),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${agent == 'all' ? '全部助手' : agent}${project.isEmpty ? '' : ' · ${project.split('/').last}'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: companionGreen,
                          ),
                        ),
                      ),
                      iconAction(
                        'X',
                        '清除筛选',
                        () => setState(() {
                          agent = 'all';
                          project = '';
                        }),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  children: [
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                        child: muted(context, g, size: 11),
                      ),
                      for (final s in rows.where((s) => group(s) == g))
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            open(s['id']);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                            backgroundColor: widget.detail?['id'] == s['id']
                                ? panelColor(context)
                                : null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              agentLogo(s['agent'], size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${s['managed'] == true ? '[独立测试] ' : ''}${s['title']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              if (s['archived'] == true)
                                glyph('Archive', size: 13),
                            ],
                          ),
                        ),
                    ],
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: muted(
                          context,
                          widget.sessions.isEmpty ? '正在读取本机会话…' : '没有匹配的会话',
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              InkWell(
                onTap: workspaceMenu,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 13,
                    horizontal: 7,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 39,
                        height: 39,
                        decoration: const BoxDecoration(
                          color: Color(0xffe5eee8),
                          shape: BoxShape.circle,
                        ),
                        child: collieMark(size: 35),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Giggle 的工作台',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: widget.online
                                        ? const Color(0xff278654)
                                        : const Color(0xffb57b3b),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                muted(
                                  context,
                                  widget.online ? '电脑已连接' : '连接中断',
                                  size: 10,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      glyph('MoreHorizontal', size: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> filters() async {
    String a = agent, p = project;
    await collieSheet<void>(
      context,
      '筛选会话',
      (ctx) => StatefulBuilder(
        builder: (ctx, change) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            muted(ctx, '选择助手和项目'),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: muted(ctx, '助手')),
                TextButton(
                  onPressed: () => change(() {
                    a = 'all';
                    p = '';
                  }),
                  child: const Text('重置'),
                ),
              ],
            ),
            LayoutBuilder(
              builder: (ctx, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final value in ['all', 'Codex', 'Hermes', 'Claude Code'])
                    SizedBox(
                      width: constraints.maxWidth < 300
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 12) / 2,
                      child: filterCard(
                        value == 'all' ? '全部' : value,
                        '${widget.sessions.where((s) => value == 'all' || s['agent'] == value).length} 个会话',
                        value == 'all'
                            ? glyph('MessageCircle', size: 20)
                            : agentLogo(value, size: 20),
                        a == value,
                        () => change(() => a = value),
                        stacked: true,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            muted(ctx, '项目'),
            const SizedBox(height: 12),
            for (final item in [
              {'name': '全部项目', 'path': ''},
              ...widget.projects,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: filterCard(
                  item['name'],
                  '${widget.sessions.where((s) => (a == 'all' || s['agent'] == a) && (item['path'] == '' || s['projectPath'] == item['path'])).length} 个会话',
                  glyph(item['path'] == '' ? 'Layers' : 'Folder', size: 17),
                  p == item['path'],
                  () => change(() => p = item['path']),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: muted(
                    ctx,
                    '${widget.sessions.where((s) => (a == 'all' || s['agent'] == a) && (p.isEmpty || s['projectPath'] == p)).length} 个匹配会话',
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      agent = a;
                      project = p;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('查看会话'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget filterCard(
    String title,
    String count,
    Widget icon,
    bool selected,
    VoidCallback action, {
    bool stacked = false,
  }) => InkWell(
    onTap: action,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: selected ? panelColor(context) : null,
        border: Border.all(
          color: selected ? const Color(0xff999999) : const Color(0xffdddddd),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    const Spacer(),
                    SizedBox(
                      width: 16,
                      height: 20,
                      child: selected ? glyph('Check', size: 16) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                muted(context, count, size: 12),
              ],
            )
          : Row(
              children: [
                icon,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      muted(context, count, size: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 16,
                  child: selected ? glyph('Check', size: 16) : null,
                ),
              ],
            ),
    ),
  );
  Future<void> workspaceMenu() async {
    await collieSheet<void>(
      context,
      'Giggle 的工作台',
      (ctx) => Column(
        children: [
          for (final item in [
            ['Monitor', '电脑与连接'],
            ['Smartphone', '手机与配对'],
            ['Bell', '通知'],
            ['Palette', '外观'],
            ['Info', '关于 G-Collie'],
            ['LogOut', '断开本设备'],
          ])
            navRow(item[0], item[1], () {
              Navigator.pop(ctx);
              settings(item[1]);
            }),
        ],
      ),
    );
  }

  Future<void> settings(String title) async {
    if (title == '电脑与连接' && widget.onManageComputers != null) {
      widget.onManageComputers!();
      return;
    }
    if (title == '内置网络') {
      await showDialog<void>(
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
      return;
    }
    if (title == '任务提醒') {
      title = '通知';
    }
    if (title == '外观') {
      await collieSheet<void>(
        context,
        title,
        (ctx) => StatefulBuilder(
          builder: (ctx, change) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('主题'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in ThemeMode.values)
                    ChoiceChip(
                      label: Text(
                        {
                          ThemeMode.light: '浅色',
                          ThemeMode.dark: '深色',
                          ThemeMode.system: '跟随系统',
                        }[m]!,
                      ),
                      selected: mode == m,
                      onSelected: (_) {
                        change(() => mode = m);
                        widget.onTheme(m);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('聊天字体大小'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final big in [false, true])
                    ChoiceChip(
                      label: Text(big ? '大号' : '标准'),
                      selected: large == big,
                      onSelected: (_) {
                        change(() => large = big);
                        widget.onFont(big);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              muted(ctx, '设置自动保存在当前设备。'),
            ],
          ),
        ),
      );
      return;
    }
    if (title == '关于 G-Collie') {
      await collieSheet<void>(
        context,
        title,
        (ctx) => Column(
          children: [
            collieMark(size: 59),
            const SizedBox(height: 12),
            const Text('G-Collie', style: TextStyle(fontSize: 25)),
            const Text('帮你照看每一个 Agent。'),
            muted(ctx, '内测版 0.3.3 · By Giggle'),
            const SizedBox(height: 20),
            const Text('Codex / Hermes 会话连接、新建、历史恢复、只读分享和工作台设置。'),
          ],
        ),
      );
      return;
    }
    if (title == '断开本设备') {
      await collieSheet<void>(
        context,
        title,
        (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('注销本设备凭证，回到配对页面。电脑上的任务会继续执行，其他设备的连接不受影响。'),
            const SizedBox(height: 20),
            outlineAction('确认断开本设备', () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              widget.onDisconnect();
            }),
            outlineAction('取消', () => Navigator.pop(ctx)),
          ],
        ),
      );
      return;
    }
    await collieSheet<void>(
      context,
      title,
      (ctx) => SettingsBody(api: widget.api, role: widget.role, title: title),
    );
  }

  Widget welcome() => ListView(
    padding: const EdgeInsets.fromLTRB(22, 24, 22, 25),
    children: [
      Image.asset(
        'assets/collie-companion-v2.png',
        width: 205,
        height: 140,
        fit: BoxFit.contain,
      ),
      const SizedBox(height: 17),
      const Text(
        '今天想继续哪项工作？',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w500,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 12),
      Center(child: muted(context, '工作在电脑，掌控在手边。', size: 13)),
      const SizedBox(height: 26),
      Row(
        children: [
          for (final a in ['Codex', 'Hermes', 'Claude Code', 'projects'])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  onTap: () {
                    if (a == 'projects') {
                      setState(() => page = 'projects');
                    } else {
                      setState(() => agent = a);
                      scaffold.currentState?.openDrawer();
                    }
                  },
                  borderRadius: BorderRadius.circular(17),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: panelColor(context),
                      border: Border.all(color: const Color(0xffe5e5e5)),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        a == 'projects'
                            ? glyph('Folder', size: 18)
                            : agentLogo(a, size: 19),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            a == 'projects' ? '浏览项目' : '$a 会话',
                            maxLines: 1,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 38),
      muted(context, '最近会话', size: 13),
      const SizedBox(height: 10),
      for (final s in widget.sessions.take(5))
        InkWell(
          onTap: () => open(s['id']),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: .15),
                ),
              ),
            ),
            child: Row(
              children: [
                agentLogo(s['agent'], size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s['managed'] == true ? '[独立测试] ' : ''}${s['title']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      muted(
                        context,
                        '${s['agent']} · ${s['project'] ?? '无项目'}',
                        size: 11,
                      ),
                    ],
                  ),
                ),
                glyph('ChevronRight', size: 17, color: mutedColor(context)),
              ],
            ),
          ),
        ),
    ],
  );
  Widget markdown(String text, {bool compact = false}) => MarkdownBody(
    data: text,
    selectable: true,
    styleSheet: MarkdownStyleSheet(
      p: TextStyle(
        fontSize: compact
            ? 13
            : large
            ? 17
            : 15,
        height: compact ? 1.65 : 1.85,
      ),
      code: TextStyle(
        fontSize: large ? 14 : 12,
        backgroundColor: panelColor(context),
      ),
      codeblockDecoration: BoxDecoration(
        color: panelColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      codeblockPadding: const EdgeInsets.all(16),
    ),
    imageBuilder: (uri, title, alt) => SessionImage(
      key: ValueKey('${widget.detail?['id']}:$uri'),
      resources: resources,
      source: uri.toString(),
      alt: alt,
    ),
    onTapLink: (_, href, _) {
      if (href != null) resources.open(context, href);
    },
  );
  Widget conversation(Json d) => ListView(
    controller: widget.scroll,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
    children: [
      Center(
        child: muted(
          context,
          d['draft'] == true
              ? '直接发送第一条消息，自动生成会话名称'
              : !widget.online
              ? '电脑连接中断 · 状态未知'
              : d['desktopLive'] == true
              ? '桌面实时连接 · ${const {'idle': '空闲', 'running': '执行中', 'waiting': '等待处理', 'starting': '加载中'}[d['status']] ?? '状态未知'} · 最近 ${d['historyLimit'] ?? 200} 条记录'
              : '桌面历史 · 运行状态未知 · 最近 ${d['historyLimit'] ?? 200} 条记录',
          size: 10,
        ),
      ),
      const SizedBox(height: 30),
      for (final e in d['events'] ?? [])
        if (e['role'] == 'tool' || e['role'] == 'reasoning')
          ProcessRecord(
            key: ValueKey('process:${d['id']}:${e['id']}'),
            record: Map<String, dynamic>.from(e),
            live:
                widget.online &&
                d['desktopLive'] == true &&
                ['running', 'starting', 'waiting'].contains(d['status']) &&
                e['turnId'] != null &&
                (e['turnId'] == d['turnId'] ||
                    (d['hermesLive'] == true &&
                        e['turnId'] == d['latestProcessTurnId'])),
          )
        else if (e['role'] == 'process')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: muted(
              context,
              '已处理 ${processDuration(e['durationMs'])}',
              size: 11,
            ),
          )
        else if (e['phase'] == 'commentary')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: markdown('${e['text']}', compact: true),
          )
        else if (e['role'] == 'user')
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: (MediaQuery.sizeOf(context).width - 40) * .85,
              ),
              margin: const EdgeInsets.only(top: 24, bottom: 32),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: panelColor(context),
                borderRadius: BorderRadius.circular(24),
              ),
              child: eventBody(Map<String, dynamic>.from(e)),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    agentLogo(d['agent'], size: 22),
                    const SizedBox(width: 8),
                    Text(
                      d['agent'],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                eventBody(Map<String, dynamic>.from(e)),
                const SizedBox(height: 8),
                iconAction(
                  'Copy',
                  '复制回复',
                  () => Clipboard.setData(ClipboardData(text: '${e['text']}')),
                  size: 16,
                ),
              ],
            ),
          ),
      if (d['liveInflight']?['assistant'] != null)
        markdown('${d['liveInflight']['assistant']}'),
      if (d['agent'] == 'Codex' &&
          RegExp(
            r'额度|usage.limit|rate.limit|quota',
            caseSensitive: false,
          ).hasMatch('${d['error'] ?? d['desktopError'] ?? ''}'))
        outlineAction('查看额度与重置卡', () => setState(() => page = 'usage')),
      if (d['desktopError'] != null) ...[
        muted(context, '${d['desktopError']}'),
        outlineAction(
          '重新连接',
          widget.loading || widget.busy ? null : () => widget.onOpen(d['id']),
        ),
      ],
      if (widget.pending != null) widget.pending!,
      const SizedBox(height: 28),
      if (d['draft'] != true)
        Center(child: muted(context, '已加载的会话记录', size: 10)),
    ],
  );
  Future<Json?> chooseSessionSettings({Json? initial}) {
    String? selectedAgent = initial?['agent'];
    String? selectedProject = initial?['cwd'];
    final options = widget.projects
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    return showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) {
          Future<void> newProject() async {
            final result = await showModalBottomSheet<Json>(
              context: ctx,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (_) => NewProjectSheet(api: widget.api),
            );
            if (result == null || !ctx.mounted) return;
            change(() {
              options.removeWhere((p) => p['path'] == result['path']);
              options.add(result);
              selectedProject = result['path'];
            });
            widget.onRefresh();
          }

          Widget card(
            double width,
            String key,
            String label,
            String? path,
            Widget icon,
            bool selected,
            VoidCallback tap, {
            bool assistant = false,
          }) => SizedBox(
            width: width,
            height: assistant ? 68 : 78,
            child: OutlinedButton(
              key: ValueKey(key),
              onPressed: tap,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(10),
                backgroundColor: selected
                    ? companionGreen.withValues(alpha: .08)
                    : null,
                side: BorderSide(
                  color: selected
                      ? companionGreen
                      : Theme.of(ctx).dividerColor.withValues(alpha: .3),
                  width: selected ? 1.5 : 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      icon,
                      const Spacer(),
                      if (selected)
                        glyph('Check', size: 17, color: companionGreen),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: assistant ? 12 : 13,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  if (path != null)
                    Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.2,
                        color: mutedColor(ctx),
                      ),
                    ),
                ],
              ),
            ),
          );
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .85,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '新会话设置',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭新会话设置',
                        onPressed: () => Navigator.pop(ctx),
                        icon: glyph('X'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: LayoutBuilder(
                        builder: (ctx, constraints) {
                          final width = (constraints.maxWidth - 12) / 2;
                          final agentWidth = (constraints.maxWidth - 20) / 3;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                '选择助手',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final name in [
                                    'Codex',
                                    'Hermes',
                                    'Claude Code',
                                  ])
                                    card(
                                      agentWidth,
                                      'session-agent:$name',
                                      name,
                                      null,
                                      agentLogo(name, size: 24),
                                      selectedAgent == name,
                                      () => change(() => selectedAgent = name),
                                      assistant: true,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                '选择项目',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  card(
                                    width,
                                    'session-new-project',
                                    '新建项目',
                                    null,
                                    glyph('Plus', size: 24),
                                    false,
                                    newProject,
                                  ),
                                  card(
                                    width,
                                    'session-project:',
                                    '无项目',
                                    '默认目录',
                                    glyph('Folder', size: 22),
                                    selectedProject == '',
                                    () => change(() => selectedProject = ''),
                                  ),
                                  for (final p in options)
                                    card(
                                      width,
                                      'session-project:${p['path']}',
                                      p['name'],
                                      p['path'],
                                      glyph('Folder', size: 22),
                                      selectedProject == p['path'],
                                      () => change(
                                        () => selectedProject = p['path'],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('session-start'),
                    onPressed: selectedAgent != null && selectedProject != null
                        ? () => Navigator.pop(ctx, {
                            'agent': selectedAgent,
                            'cwd': selectedProject,
                          })
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: companionGreen,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('开始会话'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> sessionMenu() async {
    final d = widget.detail!;
    if (d['draft'] == true) {
      final settings = await chooseSessionSettings(initial: d);
      if (settings != null && mounted) {
        widget.onOpen('draft-agent:${settings['agent']}');
        widget.onOpen('draft-project:${settings['cwd']}');
      }
      return;
    }
    await collieSheet<void>(
      context,
      d['agent'],
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(d['title'], style: const TextStyle(fontWeight: FontWeight.w600)),
          muted(ctx, d['cwd'] ?? ''),
          navRow('Info', '会话信息', () {
            Navigator.pop(ctx);
            info();
          }),
          navRow('Share2', '分享会话', () {
            Navigator.pop(ctx);
            share();
          }),
          navRow(
            'Copy',
            '复制会话 ID',
            () => Clipboard.setData(
              ClipboardData(text: '${d['nativeId'] ?? d['id']}'),
            ),
          ),
          if (d['agent'] == 'Hermes' && d['managed'] != true) ...[
            navRow('Pencil', '重命名', () {
              Navigator.pop(ctx);
              manage(false);
            }),
            navRow('Archive', '归档会话', () {
              Navigator.pop(ctx);
              manage(true);
            }),
          ],
        ],
      ),
    );
  }

  Future<void> info() => collieSheet<void>(
    context,
    '会话信息',
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.detail?['title'] ?? ''),
        SelectableText(widget.detail?['cwd'] ?? ''),
        const SizedBox(height: 12),
        muted(
          ctx,
          '${widget.detail?['model'] ?? '模型未知'} · ${widget.detail?['branch'] ?? '分支未知'}',
        ),
        SelectableText('${widget.detail?['nativeId'] ?? widget.detail?['id']}'),
      ],
    ),
  );
  Future<void> manage(bool archive) async {
    final d = widget.detail!;
    final c = TextEditingController(text: d['title']);
    String error = '';
    bool busy = false;
    await collieSheet<void>(
      context,
      archive ? '归档会话' : '重命名会话',
      (ctx) => StatefulBuilder(
        builder: (ctx, change) => Column(
          children: [
            if (archive)
              const Text('归档后会话仍保留，可在电脑端恢复。')
            else
              TextField(controller: c, maxLength: 100),
            if (error.isNotEmpty) Text(error),
            outlineAction(
              archive ? '确认归档' : '保存',
              busy
                  ? null
                  : () async {
                      change(() => busy = true);
                      try {
                        await widget.api.call(
                          '/hermes/${Uri.encodeComponent(d['nativeId'] ?? d['id'])}',
                          {
                            'action': archive ? 'archive' : 'rename',
                            'title': c.text,
                            'requestId': requestId(),
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        await widget.onRefresh();
                        if (archive) home();
                      } catch (e) {
                        change(() {
                          error = '$e';
                          busy = false;
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    c.dispose();
  }

  Future<void> share() async {
    final id = Uri.encodeComponent(widget.detail!['id']);
    dynamic result;
    String error = '';
    bool busy = false;
    await collieSheet<void>(
      context,
      '分享会话',
      (ctx) => StatefulBuilder(
        builder: (ctx, change) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('G-Collie 只读文字快照 · 7 天有效 · 需要访问电脑服务'),
            if (result != null) ...[
              const SizedBox(height: 12),
              SelectableText('${widget.api.base.resolve(result['url'])}'),
              outlineAction(
                '复制链接',
                () => Clipboard.setData(
                  ClipboardData(
                    text: '${widget.api.base.resolve(result['url'])}',
                  ),
                ),
              ),
            ],
            if (error.isNotEmpty) Text(error),
            outlineAction(
              result == null ? '创建只读快照' : '撤销分享',
              busy
                  ? null
                  : () async {
                      change(() => busy = true);
                      try {
                        final r = await widget.api.call('/share/$id', {
                          'action': result == null ? 'create' : 'revoke',
                          'key': result?['key'],
                          'requestId': requestId(),
                        });
                        change(() {
                          result = result == null ? r : null;
                          busy = false;
                        });
                      } catch (e) {
                        change(() {
                          error = '$e';
                          busy = false;
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget composer() {
    final d = widget.detail;
    final quotaBlocked = this.quotaBlocked && d?['agent'] == 'Codex';
    final hasContent =
        widget.draft.text.trim().isNotEmpty || uploads.isNotEmpty;
    final showStop = widget.running && !hasContent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 9),
            decoration: BoxDecoration(
              color: panelColor(context),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              children: [
                if (uploads.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final file in uploads)
                        Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width - 64,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xffdddddd)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              file['video'] == true
                                  ? const Icon(
                                      Icons.video_library_outlined,
                                      size: 18,
                                    )
                                  : glyph(
                                      file['image'] == true
                                          ? 'Image'
                                          : 'Paperclip',
                                      size: 18,
                                    ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      file['name'],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    if (file['video'] == true)
                                      const Text(
                                        '画面分析 · 不含音频',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.grey,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              iconAction(
                                'X',
                                '移除附件 ${file['name']}',
                                uploading || widget.busy
                                    ? null
                                    : () =>
                                          setState(() => uploads.remove(file)),
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                if (uploading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          uploadStatus,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                if (uploadError.isNotEmpty)
                  Text(
                    uploadError,
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                  ),
                TextField(
                  controller: widget.draft,
                  enabled: (widget.enabled && !quotaBlocked),
                  minLines: 1,
                  maxLines: 6,
                  maxLength: 4000,
                  onChanged: (_) => widget.onDraft(),
                  style: const TextStyle(fontSize: 14, height: 1.6),
                  decoration: InputDecoration(
                    hintText: quotaBlocked
                        ? '额度恢复后可继续，草稿会保留'
                        : !widget.online
                        ? '电脑连接后可发送'
                        : widget.loading
                        ? '正在加载历史会话…'
                        : d?['archived'] == true
                        ? '会话已归档，暂时只读'
                        : (widget.enabled && !quotaBlocked)
                        ? '向 ${d?['agent']} 发送消息…'
                        : d == null
                        ? '选择会话查看进展'
                        : '只读 · 暂不能发送消息',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    PopupMenuButton<String>(
                      tooltip: '添加附件',
                      enabled:
                          (widget.enabled && !quotaBlocked) &&
                          !uploading &&
                          widget.detail?['managed'] != true,
                      icon: glyph('Plus', size: 23),
                      onSelected: upload,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'image',
                          child: Row(
                            children: [
                              glyph('Image', size: 19),
                              const SizedBox(width: 12),
                              const Text('添加照片'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'video',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.video_library_outlined,
                                size: 19,
                              ),
                              const SizedBox(width: 12),
                              const Text('添加视频'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'file',
                          child: Row(
                            children: [
                              glyph('Paperclip', size: 19),
                              const SizedBox(width: 12),
                              const Text('上传文件'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: muted(
                        context,
                        (widget.enabled && !quotaBlocked)
                            ? (widget.running ? '桌面正在执行' : '发送到电脑上的同一会话')
                            : quotaBlocked
                            ? '等待额度恢复'
                            : !widget.online
                            ? '等待电脑连接'
                            : '只读预览',
                        size: 10,
                      ),
                    ),
                    IconButton(
                      tooltip: showStop ? '停止当前轮' : '发送',
                      onPressed:
                          (widget.enabled && (!quotaBlocked || showStop)) &&
                              !uploading &&
                              (showStop
                                  ? (d?['turnId'] != null)
                                  : (widget.draft.text.trim().isNotEmpty ||
                                        uploads.isNotEmpty))
                          ? showStop
                                ? widget.onStop
                                : () async {
                                    if (await widget.onSend(
                                          uploads
                                              .map((f) => f['id'] as String)
                                              .toList(),
                                        ) &&
                                        mounted) {
                                      setState(() => uploads.clear());
                                    }
                                  }
                          : null,
                      style: IconButton.styleFrom(
                        backgroundColor: companionGreen,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: companionGreen.withValues(
                          alpha: .35,
                        ),
                        minimumSize: const Size(32, 32),
                        fixedSize: const Size(32, 32),
                        padding: const EdgeInsets.all(6),
                      ),
                      icon: showStop
                          ? const Icon(Icons.stop, size: 16)
                          : glyph('ArrowUp', size: 20, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          muted(context, 'G-Collie · 工作在电脑执行，手机查看真实记录。', size: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    return Scaffold(
      key: scaffold,
      drawer: drawer(),
      drawerScrimColor: Colors.black.withValues(alpha: .4),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: InkWell(
          onTap: widget.onManageComputers,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.computer_outlined, size: 17),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.computerName ?? widget.api.base.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down, size: 17),
              const SizedBox(width: 10),
              SizedBox(
                width: 66,
                child: Row(
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: widget.connecting
                          ? CircularProgressIndicator(
                              strokeWidth: 1.3,
                              color: mutedColor(context),
                              semanticsLabel: '正在连接电脑',
                            )
                          : Center(
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.online
                                      ? companionGreen
                                      : mutedColor(context),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      widget.connecting
                          ? '连接中'
                          : widget.online
                          ? '已连接'
                          : '离线',
                      style: TextStyle(
                        fontSize: 11,
                        color: mutedColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        toolbarHeight: 40,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == '重新连接') {
                widget.onRefresh();
                if (widget.detail != null) widget.onOpen(widget.detail!['id']);
              } else if (v == '切换电脑') {
                widget.onManageComputers?.call();
              } else {
                settings(v);
              }
            },
            itemBuilder: (_) => [
              '任务提醒',
              '内置网络',
              '重新连接',
              '切换电脑',
            ].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    iconAction(
                      'Menu',
                      '打开会话列表',
                      () => scaffold.currentState?.openDrawer(),
                      size: 23,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: d != null && page == 'chat'
                          ? InkWell(
                              onTap: sessionMenu,
                              child: Row(
                                children: [
                                  agentLogo(d['agent'], size: 24),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      d['agent'],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  glyph(
                                    'ChevronDown',
                                    size: 15,
                                    color: mutedColor(context),
                                  ),
                                ],
                              ),
                            )
                          : Row(
                              children: [
                                collieMark(size: 29),
                                const SizedBox(width: 8),
                                const Text(
                                  'G-Collie',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    if (d != null && d['draft'] != true && page == 'chat')
                      iconAction(
                        'RefreshCw',
                        '刷新会话',
                        widget.loading ? null : () => widget.onOpen(d['id']),
                        size: 19,
                      ),
                    iconAction(
                      'SquarePen',
                      '新建会话',
                      widget.role == 'view' || widget.busy ? null : create,
                    ),
                  ],
                ),
              ),
            ),
            if (page == 'usage')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => page = 'chat'),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(d == null ? '返回会话首页' : '返回会话'),
                ),
              ),
            if (widget.error.isNotEmpty &&
                !(quotaBlocked && d?['agent'] == 'Codex'))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.error,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (widget.detail?['agent'] == 'Codex' &&
                        RegExp(
                          r'额度|usage.limit|rate.limit|quota',
                          caseSensitive: false,
                        ).hasMatch(widget.error))
                      TextButton(
                        onPressed: () => setState(() => page = 'usage'),
                        child: const Text('查看额度与重置卡'),
                      ),
                    iconAction('X', '关闭提示', widget.onClearError, size: 16),
                  ],
                ),
              ),
            if (widget.loading) const LinearProgressIndicator(minHeight: 1),
            Expanded(
              child: page == 'projects'
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const Text('项目', style: TextStyle(fontSize: 25)),
                        muted(
                          context,
                          '已关联的项目 · ${widget.projects.length} 个目录',
                        ),
                        for (final p in widget.projects)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: glyph('Folder'),
                            title: Text(p['name']),
                            subtitle: Text(
                              p['path'],
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: glyph('ChevronRight', size: 17),
                            onTap: () {
                              setState(() {
                                project = p['path'];
                                agent = 'all';
                                query = '';
                              });
                              scaffold.currentState?.openDrawer();
                            },
                          ),
                      ],
                    )
                  : page == 'usage'
                  ? UsagePage(
                      api: widget.api,
                      onOpen: open,
                      readOnly: widget.role == 'view',
                    )
                  : d == null
                  ? RefreshIndicator(
                      onRefresh: widget.onRefresh,
                      child: welcome(),
                    )
                  : conversation(d),
            ),
            if (page == 'chat' && d?['agent'] == 'Codex')
              CodexQuotaNotice(
                key: ValueKey('${widget.api.base}:quota'),
                api: widget.api,
                readOnly: widget.role == 'view',
                online: widget.online,
                error:
                    '${widget.error} ${d?['error'] ?? ''} ${d?['desktopError'] ?? ''}',
                onBlocked: (value) {
                  if (mounted && quotaBlocked != value) {
                    setState(() => quotaBlocked = value);
                  }
                },
                onRefresh: widget.onRefresh,
              ),
            if (page == 'chat' && d != null) composer(),
          ],
        ),
      ),
    );
  }
}

class SettingsBody extends StatefulWidget {
  final CollieApi api;
  final String role, title;
  const SettingsBody({
    super.key,
    required this.api,
    required this.role,
    required this.title,
  });
  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  Json? data, diagnostics;
  String error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      if (widget.title == '通知') {
        final enabled = await NativeBridge.notificationStatus();
        if (mounted) setState(() => data = {'enabled': enabled});
      }
      if (widget.title == '电脑与连接') {
        data = await widget.api.call('/network');
        try {
          diagnostics = await widget.api.call('/diagnostics');
        } catch (_) {}
      } else if (widget.title == '手机与配对' && widget.role == 'owner') {
        data = await widget.api.call('/devices');
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.title == '电脑与连接') ...[
        Text('电脑：${data?['computerName'] ?? '检测中…'}'),
        const SizedBox(height: 16),
        if (diagnostics != null) ...[
          Text(
            '服务 ${diagnostics!['version']} · 已运行 ${((diagnostics!['uptimeSeconds'] ?? 0) / 60).floor()} 分钟',
          ),
          Text(
            'Codex 控制：${diagnostics!['codex']?['controlEnabled'] == true ? '已启用' : '未启用，仅查看历史'}',
          ),
          outlineAction(
            diagnostics!['codex']?['controlEnabled'] == true
                ? '关闭 Codex 控制'
                : '启用实验性 Codex 控制',
            () async {
              try {
                await widget.api.call('/adapters/codex/control', {
                  'enabled': diagnostics!['codex']?['controlEnabled'] != true,
                });
                await load();
              } catch (e) {
                if (mounted) setState(() => error = '$e');
              }
            },
          ),
        ],
        const SizedBox(height: 16),
        Text('Tailscale：${data?['tailscale']?['state'] ?? '未安装或正在检测'}'),
        if (data?['tailscale']?['httpsURL'] != null)
          SelectableText('${data!['tailscale']['httpsURL']}'),
        for (final a in data?['addresses'] ?? []) SelectableText('$a'),
        outlineAction('重新检测连接', load),
        muted(context, '电脑须保持联网、运行服务，休眠期间无法执行任务。无论使用哪种连接，G-Collie 都要求配对。'),
      ],
      if (widget.title == '手机与配对') ...[
        Text(
          '当前权限：${widget.role == 'owner'
              ? '电脑管理端'
              : widget.role == 'view'
              ? '只读查看'
              : '控制任务'}。设备凭证保存在本设备安全存储中。',
        ),
        const SizedBox(height: 16),
        if (widget.role != 'owner')
          const Text('请在电脑管理端生成新设备配对码或管理已配对设备。')
        else
          DeviceAdmin(api: widget.api),
      ],
      if (widget.title == '通知') ...[
        Text(data?['enabled'] == true ? '后台同步已开启。' : '后台同步未运行。'),
        const SizedBox(height: 12),
        const Text(
          '开启后可在离开 App 时收到任务结束、需要处理和断线提醒。关注最近打开的 30 个会话；不显示聊天正文。首次载入、服务重启和断线期间不会推断任务完成。',
        ),
        const SizedBox(height: 12),
        muted(
          context,
          '需要通知权限，开启后会显示常驻通知。Android 对此类后台同步有时长限制，达到限制后需打开 App 重新开启。省电或强制停止可能中断同步。',
        ),
        outlineAction(data?['enabled'] == true ? '关闭提醒' : '开启提醒', () async {
          try {
            if (data?['enabled'] == true) {
              await NativeBridge.invoke<void>('notificationsStop');
            } else {
              await NativeBridge.startNotifications(widget.api);
            }
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await load();
          } catch (e) {
            if (mounted) setState(() => error = '$e');
          }
        }),
        outlineAction('发送测试通知', () async {
          try {
            final r = await widget.api.call('/push/test', {});
            if (mounted) {
              setState(
                () => error = r['sent'] == true
                    ? '测试推送已提交，请查看系统通知'
                    : '此测试入口使用浏览器推送；原生任务提醒通过任务事件同步。',
              );
            }
          } catch (e) {
            if (mounted) setState(() => error = '$e');
          }
        }),
      ],
      if (error.isNotEmpty) Text(error),
    ],
  );
}

class UsagePage extends StatefulWidget {
  final bool readOnly;
  final CollieApi api;
  final void Function(String) onOpen;
  const UsagePage({
    super.key,
    required this.api,
    required this.onOpen,
    this.readOnly = false,
  });
  @override
  State<UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends State<UsagePage> {
  Json? data;
  String agent = 'Codex', scope = 'account', tab = 'daily', error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final value = await widget.api.call('/usage?refresh=1');
      if (mounted) {
        setState(() {
          data = value;
          error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String compact(dynamic n) => n is! num
      ? '未返回'
      : n >= 1e8
      ? '${(n / 1e8).toStringAsFixed(2)} 亿'
      : n >= 1e4
      ? '${(n / 1e4).toStringAsFixed(2)} 万'
      : '$n';
  Widget tabs(
    List<String> values,
    String current,
    void Function(String) change,
  ) => Wrap(
    spacing: 7,
    children: [
      for (final v in values)
        TextButton(
          onPressed: () => setState(() => change(v)),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            backgroundColor: current == v ? panelColor(context) : null,
          ),
          child: Text(
            const {
                  'account': '账号总览',
                  'local': '本机明细',
                  'daily': '日',
                  'monthly': '月',
                  'projects': '项目',
                  'sessions': '会话',
                  'models': '模型',
                }[v] ??
                v,
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final a = data?['agents']?[agent];
    final account = data?['codexAccount'];
    final accountScope = agent == 'Codex' && scope == 'account';
    final daily = accountScope
        ? [
            for (final b in account?['usage']?['dailyUsageBuckets'] ?? [])
              {
                'date': b['startDate'],
                'usage': {'total': b['tokens']},
              },
          ]
        : a?['daily'] ?? [];
    final now = DateTime.now();
    String date(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    num? sum;
    dynamic today;
    for (final b in daily) {
      if ('${b['date']}'.startsWith(date(now).substring(0, 7))) {
        sum = (sum ?? 0) + (b['usage']?['total'] as num? ?? 0);
      }
      if (b['date'] == date(now)) today = b['usage']?['total'];
    }
    final metrics = accountScope
        ? [
            ['今日 · 账号', today],
            ['本月 · 已返回统计', sum],
            ['账号累计 Token', account?['usage']?['summary']?['lifetimeTokens']],
            ['单日最高 Token', account?['usage']?['summary']?['peakDailyTokens']],
          ]
        : [
            ['今日 Token', a?['today']?['total']],
            ['本月 Token', a?['month']?['total']],
            ['已解析累计 Token', a?['total']?['total']],
            [
              '输入缓存命中率',
              a?['total']?['cacheRate'] == null
                  ? null
                  : '${(a['total']['cacheRate'] * 100).toStringAsFixed(1)}%',
            ],
          ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Expanded(child: Text('用量统计', style: TextStyle(fontSize: 25))),
            iconAction('RefreshCw', '刷新用量统计', busy ? null : load, size: 19),
          ],
        ),
        muted(
          context,
          data == null
              ? '正在建立本地用量索引…'
              : '更新于 ${data!['generatedAt']} · ${data!['timezone']}',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            for (final value in ['Codex', 'Hermes', 'Claude Code']) ...[
              if (value != 'Codex') const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  selected: agent == value,
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      agent = value;
                      tab = 'daily';
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      backgroundColor: agent == value
                          ? panelColor(context)
                          : null,
                      side: BorderSide(
                        color: agent == value
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).dividerColor,
                        width: agent == value ? 1.5 : 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 16,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        agentLogo(value, size: 28),
                        const SizedBox(height: 10),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: agent == value
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (agent == 'Codex')
          tabs(['account', 'local'], scope, (v) {
            scope = v;
            tab = 'daily';
          }),
        const SizedBox(height: 12),
        muted(
          context,
          accountScope
              ? 'Codex 官方账号统计 · 上游数据可能延迟。每日日期沿用账号口径。'
              : agent == 'Claude Code'
              ? 'Claude Code · 主会话及子代理日志，按消息 ID 去重。输入包含缓存读取和写入，不代表账号全设备额度。'
              : '本机可解析日志 · 输入已包含缓存，推理属于输出。缺失日志的旧快照单独列出。',
        ),
        if (error.isNotEmpty) Text(error),
        if (a == null)
          muted(context, busy ? '首次统计需要读取历史日志，请稍候。' : '暂无可用统计')
        else ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final pair in metrics)
                SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 60) / 2,
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xffdddddd)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        muted(context, '${pair[0]}', size: 11),
                        const SizedBox(height: 7),
                        Text(
                          pair[1] is String ? '${pair[1]}' : compact(pair[1]),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          if (!accountScope)
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final item in [
                  ['输入', 'input'],
                  ['输出', 'output'],
                  ['缓存读取', 'cached'],
                  ['缓存写入', 'cacheWrite'],
                  ['其中推理', 'reasoning'],
                  ['已记录请求', 'requests'],
                ])
                  Text(
                    '${item[0]} ${compact(a['total']?[item[1]])}',
                    style: TextStyle(fontSize: 11, color: mutedColor(context)),
                  ),
              ],
            ),
          if (agent == 'Hermes') ...[
            const SizedBox(height: 20),
            const Text(
              '请求与费用',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text('已记录 API 请求', style: TextStyle(fontSize: 12)),
                ),
                Text('${a['total']?['requests'] ?? '未知'}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'DeepSeek 人民币参考费用',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  a['costCNY'] == null
                      ? '未知'
                      : '≈ ¥${(a['costCNY']['low'] as num).toStringAsFixed(2)}–${(a['costCNY']['high'] as num).toStringAsFixed(2)}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            muted(
              context,
              '按已记录模型 Token 和官方人民币单价估算。缺少逐请求时段，显示全空闲至全高峰范围；不是历史实扣账单。',
            ),
            muted(context, 'DeepSeek 余额、套餐额度暂未接入，不套用 Codex 的 5 小时/每周额度。'),
          ],
          if (agent == 'Codex') ...[
            const Text(
              'Codex 账号额度',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            muted(context, '账号共享额度 · 与本机 Token 总计独立'),
            for (final b in account?['limits'] ?? []) ...[
              const SizedBox(height: 16),
              Text('${b['name']}${b['plan'] == null ? '' : ' · ${b['plan']}'}'),
              for (final w in b['windows'] ?? [])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${w['windowMinutes'] == 300
                            ? '5 小时'
                            : w['windowMinutes'] == 10080
                            ? '每周'
                            : '额度窗口'} · 已用 ${w['usedPercent']}%',
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: ((w['usedPercent'] as num? ?? 0) / 100).clamp(
                          0,
                          1,
                        ),
                        color: const Color(0xff666666),
                        backgroundColor: panelColor(context),
                      ),
                      const SizedBox(height: 8),
                      muted(
                        context,
                        '剩余 ${(100 - (w['usedPercent'] as num? ?? 0)).clamp(0, 100)}% · 自动恢复：${w['resetsAt'] is num ? DateTime.fromMillisecondsSinceEpoch((w['resetsAt'] as num).toInt() * 1000).toLocal() : '未知'}',
                      ),
                    ],
                  ),
                ),
            ],
            ResetCredits(
              key: ValueKey(account?['accountKey']),
              account: account,
              api: widget.api,
              readOnly: widget.readOnly,
              onRefresh: () async {
                final value = await widget.api.call('/usage?refresh=1');
                if (mounted) setState(() => data = value);
              },
            ),
            if ((account?['limits'] as List? ?? []).isEmpty)
              muted(context, account?['limitsError'] ?? '账号未提供可显示的额度窗口'),
          ],
          const SizedBox(height: 24),
          tabs(
            accountScope
                ? ['daily', 'monthly']
                : ['daily', 'monthly', 'projects', 'sessions', 'models'],
            tab,
            (v) => tab = v,
          ),
          const SizedBox(height: 20),
          if (['daily', 'monthly'].contains(tab))
            CollieCalendar(
              key: ValueKey('$agent:$scope'),
              daily: List<dynamic>.from(daily),
              mode: tab,
            )
          else
            for (final row in a[tab] ?? [])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${row['title'] ?? row['name'] ?? row['model'] ?? ''}',
                ),
                trailing: Text(compact(row['usage']?['total'])),
                onTap: tab == 'sessions'
                    ? () => widget.onOpen(row['id'])
                    : null,
              ),
          const SizedBox(height: 18),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('统计口径与数据来源', style: TextStyle(fontSize: 12)),
            children: [
              muted(
                context,
                '总 Token = 输入 + 输出。缓存包含在输入中，推理包含在输出中。未知项不会补成 0。日/月按电脑时区统计，本机总量不等于账号全设备账单。',
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class NetworkPane extends StatefulWidget {
  const NetworkPane({super.key});
  @override
  State<NetworkPane> createState() => _NetworkPaneState();
}

class _NetworkPaneState extends State<NetworkPane> {
  Json? state;
  String error = '';
  bool busy = false, loginRequested = false, authorizing = false;
  Timer? poller;
  @override
  void initState() {
    super.initState();
    refresh();
    poller = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  @override
  void dispose() {
    poller?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    try {
      final s = await NativeBridge.network('Status');
      final url = Uri.tryParse(s['authURL'] ?? '');
      if (loginRequested &&
          url != null &&
          url.scheme == 'https' &&
          url.host == 'login.tailscale.com') {
        loginRequested = false;
        if (!await launchUrl(url, mode: LaunchMode.inAppBrowserView)) {
          throw ApiException('无法打开 App 内授权窗口，请检查默认浏览器是否支持授权');
        }
      }
      if (authorizing && s['state'] == 'Running') {
        authorizing = false;
        await NativeBridge.invoke<void>('authorizationComplete');
        NativeBridge.onNetworkReady?.call();
      }
      if (mounted) {
        setState(() {
          state = s;
          error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          state?['state'] == 'Running'
              ? '已加入私有网络，可以连接电脑'
              : state?['state'] == 'NeedsLogin'
              ? '请点击登录，授权本应用入网'
              : state?['state'] == 'NeedsMachineAuth'
              ? '等待网络管理员批准此设备'
              : '正在连接：${state?['state'] ?? '正在启动内置私有网络…'}',
        ),
        const SizedBox(height: 16),
        const Text(
          '本应用会作为独立设备加入你的 Tailscale 网络。首次在 App 内的官方授权窗口登录；不会接管其他应用的流量。电脑和手机须加入同一有访问权限的网络。',
        ),
        const SizedBox(height: 12),
        for (final p in state?['computers'] ?? [])
          TextButton(
            onPressed: () => NativeBridge.onLink?.call(p['address']),
            child: Text('${p['name']}\n${p['address']}'),
          ),
        outlineAction('登录 / 授权入网', () async {
          try {
            loginRequested = true;
            authorizing = true;
            await NativeBridge.network('Login');
            await refresh();
          } catch (e) {
            if (mounted) setState(() => error = '$e');
          }
        }),
        outlineAction('重新检测连接', refresh),
        outlineAction('退出账号', () async {
          try {
            await NativeBridge.network('Logout');
            await refresh();
          } catch (e) {
            if (mounted) setState(() => error = '$e');
          }
        }),
        if (error.isNotEmpty) Text(error),
      ],
    ),
  );
}

class CollieCalendar extends StatefulWidget {
  final List<dynamic> daily;
  final String mode;
  const CollieCalendar({super.key, required this.daily, required this.mode});
  @override
  State<CollieCalendar> createState() => _CollieCalendarState();
}

class _CollieCalendarState extends State<CollieCalendar> {
  DateTime now = DateTime.now();
  String selected = '';
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String short(num n) => n >= 1e8
      ? '${(n / 1e8).toStringAsFixed(1)}亿'
      : n >= 1e4
      ? '${(n / 1e4).toStringAsFixed(1)}万'
      : '$n';
  void move(int n) => setState(() {
    now = DateTime(
      now.year,
      now.month + (widget.mode == 'monthly' ? n * 12 : n),
      1,
    );
    selected = '';
  });
  @override
  Widget build(BuildContext context) {
    final values = <String, num>{
      for (final d in widget.daily)
        if (d['usage']?['total'] is num) d['date']: d['usage']['total'],
    };
    final max = values.values.fold<num>(1, math.max);
    final offset = DateTime(now.year, now.month, 1).weekday - 1;
    final days = DateTime(now.year, now.month + 1, 0).day;
    final weeks = ((offset + days) / 7).ceil();
    final monthly = widget.mode == 'monthly';
    final selectedValues = values.entries
        .where((e) => e.key.startsWith(selected))
        .toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .2),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              iconAction('ChevronLeft', '上一期', () => move(-1), size: 18),
              Expanded(
                child: Center(
                  child: Text(
                    '${now.year}年${monthly ? '' : ' ${now.month}月'}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              iconAction('ChevronRight', '下一期', () => move(1), size: 18),
              TextButton(
                onPressed: () => setState(() {
                  now = DateTime.now();
                  selected = key(now);
                }),
                child: const Text('今天', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (monthly)
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.2,
              children: [
                for (int m = 1; m <= 12; m++)
                  Builder(
                    builder: (ctx) {
                      final prefix =
                          '${now.year}-${m.toString().padLeft(2, '0')}';
                      final entries = values.entries
                          .where((e) => e.key.startsWith(prefix))
                          .toList();
                      return InkWell(
                        onTap: () => setState(() => selected = prefix),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: selected == prefix
                                ? panelColor(context)
                                : null,
                            border: Border.all(color: const Color(0xffdddddd)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('$m月', style: const TextStyle(fontSize: 12)),
                              Text(
                                entries.isEmpty
                                    ? '—'
                                    : short(
                                        entries.fold<num>(
                                          0,
                                          (n, e) => n + e.value,
                                        ),
                                      ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              muted(
                                context,
                                entries.isEmpty
                                    ? '未返回'
                                    : '${entries.length} 天有记录',
                                size: 9,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            )
          else ...[
            Row(
              children: [
                for (final day in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(child: Center(child: muted(context, day, size: 11))),
              ],
            ),
            const SizedBox(height: 8),
            for (int w = 0; w < weeks; w++)
              Builder(
                builder: (ctx) {
                  final recorded = <num>[];
                  final cells = <Widget>[];
                  for (int j = 0; j < 7; j++) {
                    final day = w * 7 + j - offset + 1;
                    if (day < 1 || day > days) {
                      cells.add(const Expanded(child: SizedBox(height: 52)));
                      continue;
                    }
                    final date = key(DateTime(now.year, now.month, day));
                    final n = values[date];
                    if (n != null) recorded.add(n);
                    cells.add(
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => selected = date),
                          child: Container(
                            height: 52,
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: n == null
                                  ? null
                                  : const Color(0xff2f8761).withValues(
                                      alpha: .08 + .55 * math.sqrt(n / max),
                                    ),
                              border: selected == date
                                  ? Border.all(color: companionGreen)
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$day',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 5),
                                muted(
                                  context,
                                  n == null ? '—' : short(n),
                                  size: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      Row(children: cells),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 7,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: muted(
                                context,
                                '本月第 ${w + 1} 行 · 已记录小计',
                                size: 9,
                              ),
                            ),
                            Text(
                              recorded.isEmpty
                                  ? '未返回'
                                  : '${short(recorded.fold<num>(0, (n, v) => n + v))} Token',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
          const Divider(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: muted(
              context,
              selected.isEmpty
                  ? '点击日期查看 Token 明细'
                  : '$selected · ${selectedValues.isEmpty ? '未返回用量' : '已记录 ${selectedValues.fold<num>(0, (n, e) => n + e.value)} Token'}',
              size: 11,
            ),
          ),
          const SizedBox(height: 8),
          muted(
            context,
            '— 表示未返回，不能视为 0。颜色越深，已记录用量越高。${monthly ? '' : '每周按周一开始；跨月周仅显示当前月内小计。'}',
            size: 10,
          ),
        ],
      ),
    );
  }
}

class DeviceAdmin extends StatefulWidget {
  final CollieApi api;
  const DeviceAdmin({super.key, required this.api});
  @override
  State<DeviceAdmin> createState() => _DeviceAdminState();
}

class _DeviceAdminState extends State<DeviceAdmin> {
  Json? devices, network, invite;
  String origin = '', permission = 'control', error = '';
  bool busy = false;
  Timer? clock;
  @override
  void initState() {
    super.initState();
    load();
    clock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await Future.wait([
        widget.api.call('/devices'),
        widget.api.call('/network'),
      ]);
      if (mounted) {
        setState(() {
          devices = result[0];
          network = result[1];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  List<String> get origins => [
    network?['tailscale']?['httpsURL'],
    ...network?['pairingAddresses'] ?? [],
    'http://127.0.0.1:4310',
  ].whereType<String>().where((v) => v.isNotEmpty).toSet().toList();
  Future<void> action(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = origins;
    if (!options.contains(origin)) origin = options.first;
    final valid =
        invite != null &&
        (invite!['expiresAt'] as num) > DateTime.now().millisecondsSinceEpoch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('手机访问地址', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: origin,
          key: ValueKey(origin),
          isExpanded: true,
          items: options
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (v) => setState(() {
                  origin = v!;
                  invite = null;
                }),
        ),
        const SizedBox(height: 12),
        muted(
          context,
          origin.startsWith('https:')
              ? 'HTTPS 可用于手机安装和后台推送。'
              : '此地址仅用于本机测试或显式开启的局域网访问。手机远程配对前，请先配置 Tailscale。',
        ),
        const SizedBox(height: 16),
        const Text('新设备权限', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: permission,
          items: const [
            DropdownMenuItem(value: 'control', child: Text('可控制任务')),
            DropdownMenuItem(value: 'view', child: Text('仅查看')),
          ],
          onChanged: busy
              ? null
              : (v) => setState(() {
                  permission = v!;
                  invite = null;
                }),
        ),
        const SizedBox(height: 12),
        outlineAction(
          busy ? '正在生成…' : '生成配对二维码',
          busy
              ? null
              : () => action(() async {
                  final value = await widget.api.call('/devices/pair', {
                    'role': permission,
                    'origin': origin,
                  });
                  if (mounted) setState(() => invite = value);
                }),
        ),
        if (invite != null)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 18),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: panelColor(context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (valid) ...[
                  if (invite!['qr'] is String)
                    Image.memory(
                      base64Decode((invite!['qr'] as String).split(',').last),
                      width: 220,
                      height: 220,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    '${invite!['code']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  muted(
                    context,
                    '剩余 ${(((invite!['expiresAt'] as num) - DateTime.now().millisecondsSinceEpoch) / 60000).ceil()} 分钟 · 一次有效 · 新生成会使旧码失效',
                  ),
                  outlineAction(
                    '取消本次配对',
                    busy
                        ? null
                        : () => action(() async {
                            await widget.api.call('/devices/pair/cancel', {});
                            if (mounted) setState(() => invite = null);
                          }),
                  ),
                  outlineAction(
                    '在 G-Collie APK 中打开',
                    () => launchUrl(
                      Uri(
                        scheme: 'gcollie',
                        host: 'connect',
                        queryParameters: {'url': invite!['url']},
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  const Text('配对链接'),
                  SelectableText('${invite!['url']}'),
                ] else
                  const Text('配对码已过期，请重新生成'),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          '已配对设备',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        for (final d in devices?['devices'] ?? [])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${d['name']}${d['id'] == devices?['currentDeviceId'] ? '（当前）' : ''}',
            ),
            subtitle: Text(
              d['role'] == 'owner'
                  ? '管理端'
                  : d['role'] == 'view'
                  ? '只读'
                  : '可控制',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: TextButton(
              onPressed: busy || d['id'] == devices?['currentDeviceId']
                  ? null
                  : () => action(() async {
                      await widget.api.call('/devices/${d['id']}/revoke', {});
                      await load();
                    }),
              child: const Text('撤销'),
            ),
          ),
        if (error.isNotEmpty) Text(error),
      ],
    );
  }
}
