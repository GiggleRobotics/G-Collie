import 'pairing_link.dart';
import 'about_page.dart';
import 'session_delete.dart';
import 'offline_assets.dart';
import 'sketch.dart';
import 'codex_capabilities.dart';
import 'snippets.dart';
import 'session_video.dart';
import 'dart:io';
import 'network_authorization.dart';
import 'profile.dart';
import 'network_test.dart';
import 'computers.dart';
import 'schedules.dart';
import 'downloads.dart';
import 'diagnostics.dart';
import 'quota_notice.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'account_limits.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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
const companionGreen = Color(0xff333333);
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
  builder: (c) => ['Download', 'User', 'Clock', 'Delete'].contains(name)
      ? Icon(
          name == 'Delete'
              ? Icons.delete_outline
              : name == 'Download'
              ? Icons.download_outlined
              : name == 'Clock'
              ? Icons.schedule_outlined
              : Icons.person_outline,
          size: size,
          color: color,
        )
      : SvgPicture.asset(
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
Widget outlineAction(String text, VoidCallback? action) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: OutlinedButton(
    onPressed: action,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Text(text),
  ),
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
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 16),
            child: Row(
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
                IconButton(
                  tooltip: '关闭$title',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: content(ctx),
            ),
          ),
        ],
      ),
    ),
  ),
);

Widget assistantCards(
  BuildContext context, {
  String? selected,
  required void Function(String) onSelect,
  bool enabled = true,
  String keyPrefix = 'assistant',
}) => Row(
  children: [
    for (final name in ['Codex', 'Hermes', 'Claude Code']) ...[
      if (name != 'Codex') const SizedBox(width: 8),
      Expanded(
        child: SizedBox(
          height: 88,
          child: OutlinedButton(
            key: ValueKey('$keyPrefix:$name'),
            onPressed: enabled ? () => onSelect(name) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              backgroundColor: selected == name ? panelColor(context) : null,
              side: BorderSide(
                color: selected == name
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).dividerColor,
                width: selected == name ? 1.5 : 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                agentLogo(name, size: 28),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    name,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected == name
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
);

class CollieShell extends StatefulWidget {
  final CollieApi api;
  final ThemeMode initialTheme;
  final bool initialLarge;
  final String role, error;
  final String? computerName;
  final Future<void> Function()? onManageComputers;
  final Future<void> Function()? onClearCache;
  final Future<void> Function(List<String>)? onDeleted;
  final bool connecting, reconnecting;
  final Future<void> Function()? onReconnect;
  final bool online, loading, busy, enabled, attachmentEnabled, running;
  final List<dynamic> sessions, projects, warnings;
  final Json? detail;
  final TextEditingController draft;
  final ScrollController scroll;
  final VoidCallback? onConversationMetrics, onConversationUserScroll;
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
    this.onClearCache,
    this.onDeleted,
    this.connecting = false,
    this.reconnecting = false,
    this.onReconnect,
    this.initialTheme = ThemeMode.system,
    this.initialLarge = false,
    required this.role,
    required this.error,
    required this.online,
    required this.loading,
    required this.busy,
    required this.enabled,
    required this.attachmentEnabled,
    required this.running,
    required this.sessions,
    required this.projects,
    required this.warnings,
    required this.detail,
    required this.draft,
    required this.scroll,
    this.onConversationMetrics,
    this.onConversationUserScroll,
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
    final value = _resourceSessions.putIfAbsent(
      id,
      () => SessionResources(widget.api, id),
    );
    final refs = <String>{};
    for (final event in widget.detail?['events'] as List? ?? []) {
      if (!['user', 'assistant'].contains(event['role'])) continue;
      for (final ref in event['media'] as List? ?? []) {
        if (ref is String) refs.add(ref);
      }
      for (final m in RegExp(
        r'!?\[[^\]]*\]\(([^\s)]+)\)',
      ).allMatches('${event['text'] ?? ''}')) {
        final ref = m[1]!;
        if (isSessionVideo(ref) ||
            RegExp(
              r'\.(png|jpe?g|gif|webp)([?#].*)?$',
              caseSensitive: false,
            ).hasMatch(ref)) {
          refs.add(ref);
        }
      }
    }
    value.scopeReferences = refs.toList();
    value.offline = !widget.online;
    return value;
  }

  Widget eventBody(Json e) {
    final text = '${e['text'] ?? ''}';
    final refs = <String>{
      ...List<String>.from(e['media'] ?? []),
      ...sessionVideoReferences(text),
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.isNotEmpty) markdownText(text),
        if (refs.length > 1)
          SessionGallery(
            key: ValueKey('${widget.detail?['id']}:${e['id']}:gallery'),
            resources: resources,
            sources: refs,
            videos: sessionVideoReferences(text),
          )
        else
          for (final ref in refs)
            if (isSessionVideo(ref) ||
                sessionVideoReferences(text).contains(ref))
              SessionVideo(resources: resources, source: ref)
            else
              SessionImage(resources: resources, source: ref),
      ],
    );
  }

  final scaffold = GlobalKey<ScaffoldState>();
  String query = '', agent = 'all', project = '', page = 'chat';
  bool large = false, uploading = false;
  final uploads = <Json>[];
  String uploadError = '';
  String uploadStatus = '';
  @override
  void initState() {
    super.initState();
    const FlutterSecureStorage()
        .read(key: 'project-labels:${widget.api.base}')
        .then((raw) {
          if (raw != null && mounted) {
            setState(
              () => projectLabels.addAll(
                Map<String, String>.from(jsonDecode(raw)),
              ),
            );
          }
        })
        .catchError((_) {});
    mode = widget.initialTheme;
    large = widget.initialLarge;
  }

  @override
  void didUpdateWidget(covariant CollieShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail?['id'] != widget.detail?['id']) {
      uploads.clear();
      uploadError = '';
      uploadStatus = '';
    }
  }

  bool attachmentContext(String? id) =>
      mounted &&
      id != null &&
      widget.attachmentEnabled &&
      widget.detail?['id'] == id;

  Future<void> upload(String kind) async {
    final image = kind == 'image' || kind == 'clipboard';
    final video = kind == 'video';
    if (uploading || !widget.enabled) return;
    final id = widget.detail?['id'] as String?;
    if (!attachmentContext(id)) return;
    setState(() {
      uploading = true;
      uploadError = '';
      uploadStatus = '';
    });
    String? temporaryClipboard;
    try {
      final clipboardPath = kind == 'clipboard'
          ? await NativeBridge.invoke<String>('clipboardImage')
          : null;
      temporaryClipboard = clipboardPath;
      final files = kind == 'clipboard'
          ? (clipboardPath == null ? <XFile>[] : [XFile(clipboardPath)])
          : await openFiles(
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
      // Native selectors can outlive a session switch, reconnect or permission change.
      if (!attachmentContext(id)) return;
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
        if (!attachmentContext(id)) return;
        if (length == 0 || length > (video ? 100 : 10) * 1024 * 1024) {
          throw ApiException(
            video ? '请选择不超过 100 MB 的视频' : '请选择不超过 10 MB 的非空文件',
          );
        }
        final bytes = video ? null : await f.readAsBytes();
        if (!attachmentContext(id)) return;
        final value = video
            ? await widget.api.uploadVideo(
                id!,
                f.name,
                length,
                f.openRead(),
                onProgress: (sent, total) {
                  if (attachmentContext(id)) {
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
                'data': base64Encode(bytes!),
              });
        if (!attachmentContext(id)) return;
        if (image && value['id'] is String) {
          final cache = await OfflineAssets.directory();
          if (cache != null) {
            final directory = Directory(
              '${cache.parent.path}/pending-attachments',
            );
            await directory.create(recursive: true);
            final local = File('${directory.path}/${value['id']}');
            await local.writeAsBytes(await f.readAsBytes(), flush: true);
            widget.api.attachmentPreviews[value['id']] = {
              'session': id,
              'path': local.path,
              'image': true,
            };
          }
        }
        if (kind == 'clipboard') {
          try {
            await File(f.path).delete();
          } catch (_) {}
        }
        if (!attachmentContext(id)) return;
        setState(() => uploads.add(Map<String, dynamic>.from(value)));
      }
    } catch (e) {
      if (attachmentContext(id)) setState(() => uploadError = '$e');
    } finally {
      if (temporaryClipboard != null) {
        try {
          await File(temporaryClipboard).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => uploading = false);
    }
  }

  ThemeMode mode = ThemeMode.system;
  Future<void> create([String? selectedAgent]) async {
    final settings = await chooseSessionSettings(
      initial: selectedAgent == null ? null : {'agent': selectedAgent},
    );
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
    if (value == 'projects') loadProjectUsage();
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final lowHeight = constraints.maxHeight < 560;
              Widget historyContainer(Widget child) =>
                  lowHeight ? child : Expanded(child: child);
              final children = <Widget>[
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
                  '项目管理',
                  () => nav('projects'),
                  trailing: '${widget.projects.length}',
                ),
                navRow('Activity', '用量统计', () => nav('usage')),
                navRow('Clock', '定时任务', () {
                  Navigator.pop(context);
                  showPreviewSchedules(
                    context,
                    widget.sessions,
                    widget.api,
                    canEdit: () =>
                        mounted && widget.online && widget.role != 'view',
                  );
                }),
                navRow('Download', '下载内容', () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DownloadsPage(api: widget.api),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const SizedBox(width: 10),
                    Expanded(child: muted(context, '会话')),
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
                      color: panelColor(context),
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
                historyContainer(
                  ListView(
                    shrinkWrap: lowHeight,
                    physics: lowHeight
                        ? const NeverScrollableScrollPhysics()
                        : null,
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
                          decoration: BoxDecoration(
                            color: panelColor(context),
                            shape: BoxShape.circle,
                          ),
                          child: workspaceAvatar(size: 35),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                previewWorkspaceName,
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
              ];
              return lowHeight
                  ? ListView(children: children)
                  : Column(children: children);
            },
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
    while (mounted) {
      if (!mounted) return;
      final destination = await collieSheet<String>(
        context,
        previewWorkspaceName,
        (ctx) => Column(
          children: [
            for (final item in [
              ['User', '工作台资料'],
              ['Monitor', '电脑与连接'],
              ['Bell', '通知'],
              ['Palette', '外观'],
              ['Info', '关于 G-Collie'],
              ['LogOut', '解除当前电脑配对'],
            ])
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 4,
                    ),
                    leading: glyph(item[0], size: 20),
                    title: Text(item[1], style: const TextStyle(fontSize: 14)),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () async {
                      if (item[1] == '解除当前电脑配对') {
                        await settings(item[1]);
                        return;
                      }
                      Navigator.pop(ctx, item[1]);
                    },
                  ),
                  if (item[0] != 'LogOut')
                    Divider(
                      height: 1,
                      thickness: .5,
                      color: Theme.of(ctx).dividerColor.withValues(alpha: .2),
                    ),
                ],
              ),
          ],
        ),
      );
      if (!mounted || destination == null) return;
      await settings(destination);
    }
  }

  Future<void> settings(String title) async {
    if (title == '工作台资料') {
      await editPreviewWorkspace(context);
      if (mounted) setState(() {});
      return;
    }
    if (title == '本地缓存') {
      await collieSheet<void>(
        context,
        title,
        (ctx) => Column(
          children: [
            const Text(
              '最多保留最近打开的 25 个会话；历史约 3 MiB，图片最多 50 MiB。清理不会删除电脑端会话、草稿或已下载文件。',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () async {
                await widget.onClearCache?.call();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('清理当前电脑缓存'),
            ),
          ],
        ),
      );
      return;
    }
    if (title == '故障诊断') {
      await collieSheet<void>(
        context,
        title,
        (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: DiagnosticsPage(api: widget.api, embedded: true),
        ),
      );
      return;
    }

    if (title == '电脑与连接' && widget.onManageComputers != null) {
      await widget.onManageComputers!();
      return;
    }
    if (title == '远程连接') {
      await collieSheet<void>(
        context,
        title,
        (_) => NetworkPane(api: widget.api),
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
      await collieSheet<void>(context, title, (_) => const AboutContent());
      return;
    }
    if (title == '解除当前电脑配对') {
      await collieSheet<void>(
        context,
        title,
        (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('解除本手机与当前电脑的配对，之后需重新配对。其他电脑上的任务不受影响。'),
            const SizedBox(height: 20),
            outlineAction('确认解除配对', () {
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

  final Map<String, String> projectLabels = {};
  String projectLabel(dynamic p) => projectLabels[p['path']] ?? p['name'];

  Future<void> addProjectFromList() async {
    final result = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => NewProjectSheet(api: widget.api),
    );
    if (result != null && mounted) await widget.onRefresh();
  }

  Future<void> renameProject(dynamic p) async {
    final field = TextEditingController(text: projectLabel(p));
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改显示名称'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '仅在 G-Collie 中生效，不修改电脑文件夹或桌面官方应用中的项目名称。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: field,
              maxLength: 60,
              autofocus: true,
              decoration: const InputDecoration(labelText: '显示名称'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, field.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null && value.isNotEmpty && mounted) {
      setState(() => projectLabels[p['path']] = value);
      await const FlutterSecureStorage().write(
        key: 'project-labels:${widget.api.base}',
        value: jsonEncode(projectLabels),
      );
    }
    Future<void>.delayed(const Duration(seconds: 1), field.dispose);
  }

  Future<void> projectDetails(dynamic p) => collieSheet<void>(
    context,
    '项目详情',
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          projectLabel(p),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        muted(ctx, '所属电脑', size: 12),
        const SizedBox(height: 6),
        Text((widget.computerName ?? widget.api.base.host)),
        const SizedBox(height: 20),
        muted(ctx, '工作目录', size: 12),
        const SizedBox(height: 6),
        SelectableText(p['path'], style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 16),
        muted(ctx, '显示名称仅影响 G-Collie；会话仍使用此目录。显示名称仅保存在本手机。', size: 12),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () {
            Navigator.pop(ctx);
            renameProject(p);
          },
          child: const Text('修改显示名称'),
        ),
      ],
    ),
  );

  Json? projectUsage;
  Future<void> loadProjectUsage() async {
    try {
      final data = await widget.api.call('/usage');
      if (mounted) {
        setState(() => projectUsage = Map<String, dynamic>.from(data));
      }
    } catch (_) {}
  }

  String projectTokens(dynamic p, String agent) {
    final rows = projectUsage?['agents']?[agent]?['projects'] as List?;
    if (rows == null) return '—';
    final row = rows.where((r) => r['path'] == p['path']).firstOrNull;
    if (row == null) return '—';
    final n = row['usage']?['total'];
    if (n is! num || n <= 0) return '—';
    return n >= 1000000
        ? '${(n / 1000000).toStringAsFixed(1)}M'
        : n >= 1000
        ? '${(n / 1000).toStringAsFixed(0)}K'
        : '$n';
  }

  Widget projectsPage() => ListView(
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
    children: [
      muted(
        context,
        '${widget.projects.length} 个项目 · ${(widget.computerName ?? widget.api.base.host)}',
        size: 12,
      ),
      const SizedBox(height: 22),
      if (widget.projects.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              glyph('Folder', size: 32),
              const SizedBox(height: 16),
              const Text('还没有项目'),
              const SizedBox(height: 8),
              muted(context, '关联电脑上的目录，集中查看项目会话。', size: 12),
            ],
          ),
        ),
      for (final p in widget.projects)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: panelColor(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: .15),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => projectSessions(p),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 2, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            projectLabel(p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            tooltip: '项目操作',
                            iconSize: 20,
                            onSelected: (value) {
                              if (value == 'details') {
                                projectDetails(p);
                              } else {
                                renameProject(p);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'details',
                                child: Text('项目详情'),
                              ),
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('修改显示名称'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Row(
                        children: [
                          muted(
                            context,
                            '${widget.sessions.where((s) => s['projectPath'] == p['path']).length} 会话',
                            size: 11,
                          ),
                          const Spacer(),
                          for (final entry in [
                            ('Codex', projectTokens(p, 'Codex')),
                            ('Hermes', projectTokens(p, 'Hermes')),
                            ('Claude Code', projectTokens(p, 'Claude Code')),
                          ])
                            SizedBox(
                              width: math.min(
                                72,
                                math.max(
                                  44,
                                  (MediaQuery.sizeOf(context).width - 88) / 4,
                                ),
                              ),
                              child: Tooltip(
                                message: '${entry.$1} · 累计 Token',
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    agentLogo(entry.$1, size: 14),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        entry.$2,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: .65),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Future<void> projectSessions(dynamic p) =>
      collieSheet<void>(context, projectLabel(p), (ctx) {
        final rows = widget.sessions
            .where((s) => s['projectPath'] == p['path'])
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: muted(ctx, '${rows.length} 个会话', size: 12)),
                TextButton(
                  onPressed: () => projectDetails(p),
                  child: const Text('项目详情'),
                ),
              ],
            ),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Text('这个项目还没有会话', textAlign: TextAlign.center),
              ),
            for (final session in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: agentLogo(session['agent'], size: 24),
                title: Text(
                  session['title'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  session['agent'],
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => page = 'chat');
                  open(session['id']);
                },
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: widget.role == 'view'
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      setState(() => page = 'chat');
                      widget.onCreate();
                      widget.onOpen('draft-project:${p['path']}');
                    },
              child: const Text('新建会话'),
            ),
          ],
        );
      });

  String? homeAgent;
  Widget welcome() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxHeight < 560;
      final rows = widget.sessions
          .where(
            (s) =>
                s['archived'] != true &&
                (homeAgent == null || s['agent'] == homeAgent),
          )
          .toList();
      int updated(dynamic s) => int.tryParse('${s['updatedAt']}') ?? 0;
      rows.sort((a, b) => updated(b).compareTo(updated(a)));
      final recent = rows.take(4).toList();
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact) ...[
              Image.asset(
                'assets/collie-companion-v2.png',
                height: (constraints.maxHeight * .22)
                    .clamp(100, 160)
                    .toDouble(),
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 8),
              const Text(
                '现在想继续哪项工作？',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Center(child: muted(context, '帮你照看每一个 Agent', size: 13)),
              const SizedBox(height: 16),
            ],
            assistantCards(
              context,
              selected: homeAgent,
              onSelect: (name) => setState(() => homeAgent = name),
              enabled: !widget.busy,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: muted(
                    context,
                    homeAgent == null ? '最近使用' : '$homeAgent · 最近会话',
                    size: 13,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      agent = homeAgent ?? 'all';
                      project = '';
                      query = '';
                    });
                    scaffold.currentState?.openDrawer();
                  },
                  child: const Text('查看全部会话'),
                ),
              ],
            ),
            Expanded(
              child: recent.isEmpty
                  ? Center(
                      child: muted(
                        context,
                        homeAgent == null ? '暂无会话，点击右上角新建' : '$homeAgent 暂无会话',
                        size: 13,
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, area) {
                        final height = area.maxHeight / 4;
                        return Column(
                          children: [
                            for (final s in recent)
                              SizedBox(
                                key: ValueKey('home-recent:${s['id']}'),
                                height: height,
                                child: InkWell(
                                  onTap: () => open(s['id']),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Theme.of(
                                            context,
                                          ).dividerColor.withValues(alpha: .15),
                                        ),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: Row(
                                      children: [
                                        agentLogo(s['agent'], size: 24),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${s['managed'] == true ? '[独立测试] ' : ''}${s['title']}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                              ),
                                              if (height >= 46) ...[
                                                const SizedBox(height: 4),
                                                muted(
                                                  context,
                                                  '${s['agent']} · ${s['project'] ?? '无项目'}',
                                                  size: 11,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        glyph(
                                          'ChevronRight',
                                          size: 17,
                                          color: mutedColor(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );

  Widget markdown(String text, {bool compact = false}) {
    final videos = sessionVideoReferences(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        markdownText(text, compact: compact),
        for (final ref in videos)
          SessionVideo(
            key: ValueKey('video:$ref'),
            resources: resources,
            source: ref,
          ),
      ],
    );
  }

  Widget markdownText(String text, {bool compact = false}) => MarkdownBody(
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
    imageBuilder: (uri, title, alt) => isSessionVideo(uri.toString())
        ? SessionVideo(resources: resources, source: uri.toString())
        : SessionImage(
            key: ValueKey('${widget.detail?['id']}:$uri'),
            resources: resources,
            source: uri.toString(),
            alt: alt,
          ),
    onTapLink: (label, href, _) {
      if (href == null) return;
      final uri = Uri.tryParse(href);
      final local = uri != null && !['http', 'https'].contains(uri.scheme);
      if (local &&
          RegExp(
            r'^(下载|download\b)',
            caseSensitive: false,
          ).hasMatch(label.trim())) {
        resources.download(context, href);
      } else {
        resources.open(context, href);
      }
    },
  );
  Widget conversation(Json d) => NotificationListener<UserScrollNotification>(
    onNotification: (notification) {
      if (notification.depth == 0 &&
          notification.direction != ScrollDirection.idle) {
        widget.onConversationUserScroll?.call();
      }
      return false;
    },
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) widget.onConversationMetrics?.call();
        return false;
      },
      child: ListView(
        controller: widget.scroll,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          if (d['draft'] != true &&
              (d['localHistory'] == true || !widget.online))
            Center(
              child: muted(
                context,
                d['localHistory'] == true
                    ? d['uncached'] == true
                          ? '此会话尚未缓存，连接电脑后可加载历史'
                          : '本地历史 · 上次同步 ${d['lastSyncedAt'] ?? '时间未知'}'
                    : !widget.online
                    ? '本地历史 · 电脑暂不可达'
                    : d['desktopLive'] == true
                    ? '桌面实时连接 · ${const {'idle': '空闲', 'running': '执行中', 'waiting': '等待处理', 'starting': '加载中'}[d['status']] ?? '状态未知'}'
                    : '桌面历史 · 运行状态未知',
                size: 10,
              ),
            ),
          if (d['draft'] != true &&
              (d['localHistory'] == true || !widget.online))
            const SizedBox(height: 8),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: panelColor(context),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      eventBody(Map<String, dynamic>.from(e)),
                      if (e['sendStatus'] != null)
                        muted(
                          context,
                          const {
                                'sending': '发送中…',
                                'sent': '已发送 · 等待记录同步',
                                'failed': '发送失败，请检查提示后重试',
                                'unknown': '发送结果未知，请勿重复发送',
                              }[e['sendStatus']] ??
                              '',
                          size: 10,
                        ),
                    ],
                  ),
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
                      () => Clipboard.setData(
                        ClipboardData(text: '${e['text']}'),
                      ),
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
              widget.loading || widget.busy
                  ? null
                  : () => widget.onOpen(d['id']),
            ),
          ],
          if (widget.pending != null) widget.pending!,
          const SizedBox(height: 28),
          if (d['draft'] != true &&
              (d['localHistory'] == true || !widget.online))
            Center(child: muted(context, '已加载的会话记录', size: 10)),
        ],
      ),
    ),
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
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
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
                              assistantCards(
                                keyPrefix: 'session-agent',
                                ctx,
                                selected: selectedAgent,
                                onSelect: (name) =>
                                    change(() => selectedAgent = name),
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
          navRow('Delete', '删除会话', () {
            Navigator.pop(ctx);
            deleteSession();
          }),
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

  Future<void> deleteSession() async {
    final d = Map<String, dynamic>.from(widget.detail!);
    final id = d['id'] as String;
    await collieSheet<void>(
      context,
      '删除会话',
      (ctx) => SessionDeletePanel(
        detail: d,
        computer: widget.computerName ?? widget.api.base.host,
        blocked: !widget.online
            ? '电脑离线，恢复连接后再删除。'
            : widget.role == 'view'
            ? '当前连接只读，无法删除会话。'
            : widget.busy ||
                  widget.loading ||
                  d['draft'] == true ||
                  ['running', 'starting', 'waiting'].contains(d['status'])
            ? '任务执行中或等待处理，暂不可删除。不会自动停止任务。'
            : null,
        eligibility: () async => Map<String, dynamic>.from(
          await widget.api.call(
            '/local/${Uri.encodeComponent(id)}/delete-eligibility',
          ),
        ),
        remove: (request) async => Map<String, dynamic>.from(
          await widget.api.call('/local/${Uri.encodeComponent(id)}/delete', {
            'requestId': request,
          }),
        ),
        onDeleted: (ids) async {
          if (widget.onDeleted != null) {
            await widget.onDeleted!(ids);
          } else {
            home();
            await widget.onRefresh();
          }
          if (ctx.mounted) Navigator.pop(ctx);
        },
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

  Future<void> attachmentMenu() async {
    final sessionId = widget.detail?['id'] as String?;
    if (!widget.enabled || !attachmentContext(sessionId)) return;
    final kind = await collieSheet<String>(
      context,
      '添加',
      (ctx) => Column(
        children: [
          for (final entry in [
            ['image', '添加照片', Icons.image_outlined],
            ['video', '添加视频', Icons.video_library_outlined],
            ['file', '手机文件', Icons.attach_file],
            ['folder', '引用电脑目录', Icons.folder_outlined],
            if (widget.detail?['agent'] == 'Codex')
              ['codex-capabilities', '目标、计划与插件', Icons.tune],
            if (widget.detail?['agent'] == 'Codex')
              ['sketch', 'Sketch 草图', Icons.draw_outlined],
            if (widget.detail?['agent'] == 'Hermes') ...[
              ['url', '添加网址', Icons.link],
              ['snippet', '提示词片段', Icons.short_text],
              ['clipboard', '粘贴图片', Icons.content_paste],
            ],
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(entry[2] as IconData, size: 22),
              title: Text(entry[1] as String),
              onTap: () => Navigator.pop(ctx, entry[0] as String),
            ),
        ],
      ),
    );
    if (!mounted || kind == null || !attachmentContext(sessionId)) return;
    if (['image', 'video', 'file', 'clipboard'].contains(kind)) {
      await upload(kind);
      return;
    }
    if (kind == 'codex-capabilities') {
      final selection = await Navigator.of(context).push<Json>(
        MaterialPageRoute(
          builder: (_) => CodexCapabilities(
            api: widget.api,
            session: '${widget.detail!['id']}',
            enabled: widget.enabled,
          ),
        ),
      );
      if (selection != null && attachmentContext(sessionId)) {
        if (uploads.length >= 5) {
          setState(() => uploadError = '每条消息最多添加 5 个附件或技能');
        } else {
          setState(
            () => uploads.add({
              'id': 'skill:${selection['skillId']}',
              'name': selection['name'],
              'mime': 'application/x-codex-skill',
              'size': 0,
              'image': false,
            }),
          );
        }
      }
      return;
    }
    if (kind == 'sketch') {
      final id = widget.detail?['id'];
      final bytes = await Navigator.of(
        context,
      ).push<Uint8List>(MaterialPageRoute(builder: (_) => const SketchPage()));
      if (bytes != null &&
          mounted &&
          widget.enabled &&
          widget.detail?['id'] == id) {
        try {
          if (uploads.length >= 5) throw ApiException('每条消息最多添加 5 个附件');
          setState(() => uploading = true);
          final result = await widget.api.call('/attachments', {
            'session': id,
            'name': 'sketch.png',
            'image': true,
            'data': base64Encode(bytes),
          });
          if (mounted && widget.detail?['id'] == id) {
            setState(() => uploads.add(Map<String, dynamic>.from(result)));
          }
        } catch (e) {
          if (mounted) setState(() => uploadError = '$e');
        } finally {
          if (mounted) setState(() => uploading = false);
        }
      }
      return;
    }
    if (kind == 'snippet') {
      final value = await Navigator.of(
        context,
      ).push<String>(MaterialPageRoute(builder: (_) => const SnippetLibrary()));
      if (attachmentContext(sessionId) && value != null) appendContext(value);
      return;
    }
    if (kind == 'folder') {
      final folder = await Navigator.of(context).push<Json>(
        MaterialPageRoute(
          builder: (_) => ComputerFolders(api: widget.api, create: false),
        ),
      );
      if (folder != null && attachmentContext(sessionId)) {
        appendContext('电脑目录：${folder['path']}');
      }
      return;
    }
    final field = TextEditingController();
    final value = await collieSheet<String>(
      context,
      kind == 'url' ? '添加网址' : '提示词片段',
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: field,
            autofocus: true,
            minLines: 1,
            maxLines: kind == 'url' ? 1 : 6,
            decoration: InputDecoration(
              hintText: kind == 'url'
                  ? 'https://example.com'
                  : '输入常用提示词，插入后仍可编辑',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, field.text.trim()),
            child: const Text('插入草稿'),
          ),
        ],
      ),
    );
    if (mounted &&
        attachmentContext(sessionId) &&
        value != null &&
        value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (kind == 'url' &&
          (uri == null ||
              !['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请输入完整 http 或 https 网址')));
      } else {
        appendContext(value);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    field.dispose();
  }

  void appendContext(String value) {
    final text = widget.draft.text;
    final selection = widget.draft.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final insert = '${start > 0 ? '\n' : ''}$value';
    final result = text.replaceRange(start, end, insert);
    if (result.length > 4000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('消息超过 4000 字，请精简后添加')));
      return;
    }
    widget.draft.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    widget.onDraft();
    setState(() {});
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                Row(
                  children: [
                    IconButton(
                      tooltip: '添加附件',
                      onPressed:
                          widget.enabled &&
                              !quotaBlocked &&
                              !uploading &&
                              widget.detail?['managed'] != true
                          ? attachmentMenu
                          : null,
                      icon: glyph('Plus', size: 23),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: widget.draft,
                        enabled:
                            widget.role != 'view' &&
                            !widget.busy &&
                            !widget.loading &&
                            widget.detail != null,
                        minLines: 1,
                        maxLines: 1,
                        maxLength: 4000,
                        onChanged: (_) => widget.onDraft(),
                        style: const TextStyle(fontSize: 14, height: 1.6),
                        decoration: InputDecoration(
                          hintText: quotaBlocked
                              ? '额度恢复后可继续，草稿会保留'
                              : !widget.online
                              ? '离线草稿，连接后由你确认发送'
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
                    ),
                    const SizedBox(width: 8),
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
        titleSpacing: 20,
        foregroundColor: mutedColor(context),
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onManageComputers,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.computer_outlined, size: 15),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.computerName ?? widget.api.base.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down, size: 15),
                const SizedBox(width: 10),
                SizedBox(
                  width: widget.connecting || !widget.online ? 66 : 10,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: widget.connecting
                            ? CircularProgressIndicator(
                                strokeWidth: 1.3,
                                color: const Color(0xffb88a00),
                                semanticsLabel: '正在连接电脑',
                              )
                            : Center(
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: !widget.online
                                        ? const Color(0xffef4444)
                                        : const Color(0xff00d600),
                                  ),
                                ),
                              ),
                      ),
                      if (widget.connecting || !widget.online)
                        const SizedBox(width: 5),
                      if (widget.connecting || !widget.online)
                        Text(
                          widget.connecting
                              ? '连接中'
                              : !widget.online
                              ? '未连接'
                              : '已连接',
                          style: const TextStyle(fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        toolbarHeight: 40,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              if (v == '重新连接') {
                await (widget.onReconnect ?? widget.onRefresh)();
              } else if (v == '切换电脑') {
                widget.onManageComputers?.call();
              } else {
                settings(v);
              }
            },
            itemBuilder: (_) => ['任务提醒', '远程连接', '故障诊断', '本地缓存', '重新连接', '切换电脑']
                .map(
                  (v) => PopupMenuItem(
                    value: v,
                    enabled: v != '重新连接' || !widget.reconnecting,
                    child: Text(
                      v == '重新连接' && widget.reconnecting ? '正在重新连接…' : v,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (page != 'chat' || d != null)
                      IconButton(
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: '返回会话首页',
                        onPressed: home,
                        icon: const Icon(Icons.arrow_back, size: 23),
                      )
                    else
                      iconAction(
                        'Menu',
                        '打开会话列表',
                        () => scaffold.currentState?.openDrawer(),
                        size: 23,
                      ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: page != 'chat'
                          ? Text(
                              page == 'projects' ? '项目管理' : '用量统计',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : d != null
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
                    if (page == 'projects')
                      iconAction(
                        'Plus',
                        '新建项目',
                        widget.role == 'view' ? null : addProjectFromList,
                      )
                    else if (page == 'chat')
                      iconAction(
                        'SquarePen',
                        '新建会话',
                        widget.role == 'view' || widget.busy ? null : create,
                      ),
                  ],
                ),
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
              key: const ValueKey('workspace-content'),
              child: page == 'projects'
                  ? projectsPage()
                  : page == 'usage'
                  ? UsagePage(
                      api: widget.api,
                      onOpen: open,
                      readOnly: widget.role == 'view',
                    )
                  : d == null
                  ? welcome()
                  : Stack(
                      children: [
                        Positioned.fill(child: conversation(d)),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 12,
                          child: Center(
                            child: AnimatedBuilder(
                              animation: widget.scroll,
                              builder: (context, _) =>
                                  widget.scroll.positions.length == 1 &&
                                      widget
                                          .scroll
                                          .position
                                          .hasContentDimensions &&
                                      widget.scroll.position.extentAfter > 160
                                  ? Material(
                                      elevation: 2,
                                      shape: const CircleBorder(),
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surface,
                                      child: IconButton(
                                        tooltip: '跳到最新消息',
                                        icon: const Icon(
                                          Icons.arrow_downward,
                                          size: 21,
                                        ),
                                        onPressed: () =>
                                            widget.scroll.animateTo(
                                              widget
                                                  .scroll
                                                  .position
                                                  .maxScrollExtent,
                                              duration: const Duration(
                                                milliseconds: 250,
                                              ),
                                              curve: Curves.easeOut,
                                            ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ],
                    ),
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
                onUsage: () => setState(() => page = 'usage'),
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
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
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
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.title == '电脑与连接') ...[
        Text('电脑：${data?['computerName'] ?? '检测中…'}'),
        const SizedBox(height: 16),
        SelectableText('服务地址：${widget.api.base}'),
        if (diagnostics != null)
          Text(
            '服务：${(diagnostics!['checks'] as List?)?.firstOrNull?['status'] ?? '暂不可用'}',
          ),
        const SizedBox(height: 12),
        outlineAction(busy ? '正在检测…' : '重新检测连接', busy ? null : load),
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

class _UsagePageState extends State<UsagePage> with WidgetsBindingObserver {
  Timer? refreshTimer;
  Json? data;
  String agent = 'Codex', scope = 'account', tab = 'daily', error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!busy) load();
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) load();
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
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: muted(
                context,
                data == null
                    ? '正在建立本地用量索引…'
                    : '更新于 ${data!['generatedAt']} · ${data!['timezone']}',
              ),
            ),
            iconAction('RefreshCw', '刷新用量统计', busy ? null : load, size: 19),
          ],
        ),
        const SizedBox(height: 20),
        assistantCards(
          context,
          selected: agent,
          onSelect: (value) => setState(() {
            agent = value;
            tab = 'daily';
          }),
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
        if (error.isNotEmpty) ...[
          Text(error),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: busy ? null : load,
              child: const Text('重试'),
            ),
          ),
        ],
        if (a == null && error.isEmpty)
          muted(context, busy ? '首次统计需要读取历史日志，请稍候。' : '暂无可用统计')
        else if (a != null) ...[
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
          if (agent == 'Codex')
            AccountLimits(
              account: account,
              api: widget.api,
              readOnly: widget.readOnly,
              onRefresh: () async {
                final value = await widget.api.call('/usage?refresh=1');
                if (mounted) setState(() => data = value);
              },
            ),
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
  final CollieApi? api;
  const NetworkPane({super.key, this.api});
  @override
  State<NetworkPane> createState() => _NetworkPaneState();
}

class _NetworkPaneState extends State<NetworkPane> {
  ConnectionTest? test;
  Json? result;
  String testStatus = '';
  bool testing = false;
  Future<void> testConnection() async {
    if (testing || widget.api == null) return;
    final current = ConnectionTest(widget.api!);
    test = current;
    setState(() {
      testing = true;
      result = null;
      testStatus = '正在测试…';
    });
    try {
      final value = await current.run((message) {
        if (mounted) setState(() => testStatus = message);
      });
      if (mounted) {
        setState(() {
          result = value;
          testStatus = '电脑服务可达 · 测试完成';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => testStatus = current.cancelled
              ? '测试已取消或达到 20 秒上限'
              : '$testStatus\n${e is TimeoutException
                    ? '此阶段超时，请检查当前连接后重试'
                    : e is IOException
                    ? '连接在测试中中断，请等待连接恢复后重试'
                    : '测试失败：$e'}',
        );
      }
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Json? state;
  String error = '';
  bool busy = false, loginRequested = false;
  Timer? poller;
  @override
  void initState() {
    super.initState();
    refresh();
    poller = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  @override
  void dispose() {
    test?.cancel();
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
        if (!mounted) return;
        final authorized = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => NetworkAuthorizationPage(url: url)),
        );
        if (authorized == true) NativeBridge.onNetworkReady?.call();
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
            child: Text(
              '${p['name']}\n${p['address']}',
              textAlign: TextAlign.center,
            ),
          ),
        outlineAction('登录 / 授权入网', () async {
          try {
            loginRequested = true;
            await NativeBridge.network('Login');
            await refresh();
          } catch (e) {
            if (mounted) setState(() => error = '$e');
          }
        }),
        const SizedBox(height: 12),
        outlineAction(
          testing ? '测试中…' : '测试连接',
          testing || widget.api == null ? null : testConnection,
        ),
        if (widget.api == null) const Text('连接电脑后可测试该连接。'),
        if (testing)
          TextButton(
            onPressed: () => test?.cancel(),
            child: const Text('取消测试'),
          ),
        if (testStatus.isNotEmpty) Text(testStatus),
        if (result != null) ...[
          Text(
            '平均延时：${(result!['averageMs'] as num).toStringAsFixed(1)} ms · 波动：${(result!['variationMs'] as num).toStringAsFixed(1)} ms',
          ),
          Text(
            '下载：${(result!['downloadMbps'] as num).toStringAsFixed(2)} Mbps · 上传：${(result!['uploadMbps'] as num).toStringAsFixed(2)} Mbps',
          ),
          Text('测试时间：${result!['time']}'),
        ],
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
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withValues(
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

class AddComputerPane extends StatefulWidget {
  final ComputerStore computers;
  const AddComputerPane({super.key, required this.computers});
  @override
  State<AddComputerPane> createState() => _AddComputerPaneState();
}

class _AddComputerPaneState extends State<AddComputerPane> {
  final address = TextEditingController(), code = TextEditingController();
  bool busy = false;
  String error = '';
  Future<void> pair() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    CollieApi? client;
    try {
      final raw = Uri.parse(address.text.trim());
      final base = serverUri(raw.replace(fragment: '').toString());
      final invite = parsePairingLink(address.text)?.code;
      if (raw.hasFragment && invite == null) {
        throw const FormatException('无效配对链接');
      }
      client = CollieApi(
        base,
        cookie: '',
        saveCookie: (value) =>
            widget.computers.storage.write(key: 'cookie:$base', value: value),
      );
      await NativeBridge.connect(client);
      final result = await client.call('/auth/pair', {
        'code': invite ?? code.text.trim(),
        'name': '我的手机',
      });
      await widget.computers.remember(
        base,
        result['device']['role'],
        select: false,
      );
      if (mounted) Navigator.pop(context, '$base');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      client?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    address.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('添加不会断开当前电脑。取消后返回电脑列表。'),
      const SizedBox(height: 16),
      TextField(
        controller: address,
        inputFormatters: [PairingLinkFormatter(address: address, code: code)],
        enabled: !busy,
        decoration: const InputDecoration(
          labelText: '服务地址或完整配对链接',
          hintText: 'http://100.x.x.x:4310',
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: code,
        inputFormatters: [PairingLinkFormatter(address: address, code: code, codeField: true)],
        enabled: !busy,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(labelText: '配对码（完整配对链接可不填）'),
      ),
      if (error.isNotEmpty)
        Text(
          error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      FilledButton(
        onPressed: busy ? null : pair,
        child: Text(busy ? '正在配对…' : '配对并连接'),
      ),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );
}
