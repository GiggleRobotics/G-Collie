import 'connection_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'api.dart';

Future<void> showPreviewSchedules(
  BuildContext context,
  List<dynamic> sessions,
  CollieApi api,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => SchedulePreview(sessions: sessions, api: api),
  ),
);

class SchedulePreview extends StatefulWidget {
  final CollieApi api;
  final List<dynamic> sessions;
  const SchedulePreview({super.key, required this.sessions, required this.api});
  @override
  State<SchedulePreview> createState() => _SchedulePreviewState();
}

class _SchedulePreviewState extends State<SchedulePreview> {
  Timer? refreshTimer;
  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> demoSchedules = [];
  String loadError = '';
  @override
  void initState() {
    super.initState();
    load();
    refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => load());
  }

  Future<void> load() async {
    try {
      final r = await widget.api.call('/schedules');
      if (mounted) {
        setState(
          () => demoSchedules = (r['tasks'] as List).map((e) {
            final m = Map<String, dynamic>.from(e);
            m['time'] = DateTime.fromMillisecondsSinceEpoch(m['time']);
            m['repeat'] = m['interval'] == 18000000
                ? '每 5 小时'
                : m['interval'] == 86400000
                ? '每天'
                : '仅一次';
            return m;
          }).toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => loadError = '$e');
    }
  }

  Future<void> mutate(String path, [Json? data]) async {
    try {
      if (data == null) {
        await widget.api.call('$path/cancel', {});
      } else {
        await widget.api.call(path, data);
      }
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> edit([Map<String, dynamic>? old]) async {
    final sessions = widget.sessions
        .where((s) => s['agent'] == 'Codex')
        .toList();
    String session = old?['session'] as String? ?? 'new';
    final initial =
        old?['time'] as DateTime? ??
        DateTime.now().add(const Duration(hours: 1));
    int hour = initial.hour, minute = initial.minute;
    String repeat = old?['repeat'] as String? ?? '仅一次';
    final text = TextEditingController(text: old?['text'] as String? ?? '');
    final hourController = FixedExtentScrollController(initialItem: hour);
    final minuteController = FixedExtentScrollController(initialItem: minute);
    String? error;
    DateTime nextTime() {
      final now = DateTime.now();
      final value = DateTime(now.year, now.month, now.day, hour, minute);
      return value.isAfter(now) ? value : value.add(const Duration(days: 1));
    }

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, change) {
            final muted = Theme.of(
              ctx,
            ).colorScheme.onSurface.withValues(alpha: .5);
            return ConnectionPage(
              api: widget.api,
              appBar: AppBar(
                title: Text(
                  old == null ? '添加定时消息' : '编辑定时消息',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    12,
                    22,
                    16 + MediaQuery.viewInsetsOf(ctx).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '来源电脑需在线；错过时间不自动补发',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(
                              ctx,
                            ).colorScheme.onSurface,
                            foregroundColor: Theme.of(
                              ctx,
                            ).scaffoldBackgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            if (text.text.trim().isEmpty) {
                              change(() => error = '请填写消息内容');
                              return;
                            }
                            Navigator.pop(ctx, true);
                          },
                          child: const Text('保存定时消息'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                children: [
                  SizedBox(
                    height: 220,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          child: CupertinoPicker(
                            scrollController: hourController,
                            itemExtent: 48,
                            onSelectedItemChanged: (v) =>
                                change(() => hour = v),
                            children: [
                              for (int h = 0; h < 24; h++)
                                Center(
                                  child: Text(
                                    h.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: 32,
                                      color: Theme.of(
                                        ctx,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Text(':', style: TextStyle(fontSize: 28)),
                        SizedBox(
                          width: 100,
                          child: CupertinoPicker(
                            scrollController: minuteController,
                            itemExtent: 48,
                            onSelectedItemChanged: (v) =>
                                change(() => minute = v),
                            children: [
                              for (int m = 0; m < 60; m++)
                                Center(
                                  child: Text(
                                    m.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: 32,
                                      color: Theme.of(
                                        ctx,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: Text(
                      '${nextTime().day == DateTime.now().day ? '今天' : '明天'} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} · 当前设备时区',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('重复', style: TextStyle(fontSize: 14)),
                      ),
                      DropdownButton<String>(
                        value: repeat,
                        underline: const SizedBox(),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(ctx).colorScheme.onSurface,
                        ),
                        items: [
                          for (final r in ['仅一次', '每天', '每 5 小时'])
                            DropdownMenuItem(value: r, child: Text(r)),
                        ],
                        onChanged: (v) => change(() => repeat = v!),
                      ),
                    ],
                  ),
                  Divider(
                    color: Theme.of(ctx).dividerColor.withValues(alpha: .15),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '消息内容',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: text,
                    minLines: 1,
                    maxLines: 6,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      hintText: '输入要发送的消息，例如：1',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('发送到', style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      session == 'new'
                          ? '新建会话（默认）'
                          : sessions
                                    .where((s) => s['id'] == session)
                                    .map((s) => s['title'] as String)
                                    .firstOrNull ??
                                '会话不可用，请重新选择',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () async {
                      final selected = await showModalBottomSheet<String>(
                        context: ctx,
                        useSafeArea: true,
                        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
                        builder: (sheet) => SafeArea(
                          child: SizedBox(
                            height: MediaQuery.sizeOf(sheet).height * .55,
                            child: Column(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(22),
                                  child: Text(
                                    '选择会话',
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: ListView(
                                    children: [
                                      ListTile(
                                        title: const Text('新建会话'),
                                        subtitle: const Text('默认'),
                                        trailing: session == 'new'
                                            ? const Icon(Icons.check, size: 20)
                                            : null,
                                        onTap: () =>
                                            Navigator.pop(sheet, 'new'),
                                      ),
                                      for (final s in sessions)
                                        ListTile(
                                          title: Text(
                                            s['title'] as String,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            s['project'] as String? ?? 'Codex',
                                          ),
                                          trailing: session == s['id']
                                              ? const Icon(
                                                  Icons.check,
                                                  size: 20,
                                                )
                                              : null,
                                          onTap: () => Navigator.pop(
                                            sheet,
                                            s['id'] as String,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (selected != null && ctx.mounted) {
                        change(() => session = selected);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    if (saved == true && mounted) {
      await mutate(old == null ? '/schedules' : '/schedules/${old['id']}', {
        'session': session,
        'text': text.text.trim(),
        'time': nextTime().millisecondsSinceEpoch,
        'interval': repeat == '每天'
            ? 86400000
            : repeat == '每 5 小时'
            ? 18000000
            : 0,
        'enabled': old?['enabled'] ?? true,
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    hourController.dispose();
    minuteController.dispose();
    text.dispose();
  }

  @override
  Widget build(BuildContext context) => ConnectionPage(
    api: widget.api,
    appBar: AppBar(
      leading: IconButton(
        tooltip: '返回',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back, size: 23),
      ),
      title: const Text(
        '定时消息',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
      ),
      actions: [
        IconButton(
          tooltip: '新建定时消息',
          onPressed: edit,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        if (loadError.isNotEmpty) Text(loadError),
        const Text(
          '安排下一条消息',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        const Text(
          '任务由当前电脑执行，手机可离线。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        if (demoSchedules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                const Icon(
                  Icons.schedule_outlined,
                  size: 38,
                  color: Colors.grey,
                ),
                const SizedBox(height: 18),
                const Text('还没有定时消息'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: edit,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建定时消息'),
                ),
              ],
            ),
          ),
        for (final task in demoSchedules)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: .15),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${task['repeat']} · ${task['status'] == 'sent'
                            ? '已发送'
                            : task['status'] == 'failed'
                            ? '发送失败'
                            : task['status'] == 'unknown'
                            ? '结果未知'
                            : task['enabled'] == true
                            ? '待发送'
                            : '已暂停'}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Switch(
                      value: task['enabled'] == true,
                      onChanged: (v) =>
                          mutate('/schedules/${task['id']}', {'enabled': v}),
                    ),
                  ],
                ),
                Text(
                  '${task['time']}'.substring(0, 16),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.sessions
                          .where((s) => s['id'] == task['session'])
                          .map((s) => s['title'])
                          .firstOrNull ??
                      '新建 Codex 会话',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                if (task['error'] != null)
                  Text(
                    task['error'],
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                Text(
                  task['text'],
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => edit(task),
                      child: const Text('编辑'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('取消此定时消息？'),
                            content: const Text('取消后不会再按此计划发送。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('返回'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('确认取消'),
                              ),
                            ],
                          ),
                        );
                        if (yes == true && mounted) {
                          mutate('/schedules/${task['id']}');
                        }
                      },
                      child: const Text('取消任务'),
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
