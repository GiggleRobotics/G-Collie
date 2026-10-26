import 'section_app_bar.dart';
import 'diagnostic_log.dart';
import 'diagnostic_sync.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'native.dart';

class DiagnosticsPage extends StatefulWidget {
  final CollieApi api;
  final bool embedded;
  const DiagnosticsPage({super.key, required this.api, this.embedded = false});
  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  List<dynamic> checks = [];
  List<dynamic> recent = [];
  List<dynamic> phoneEvents = [];
  bool busy = false, uploading = false;
  DateTime from = DateTime.now().subtract(const Duration(hours: 1)),
      to = DateTime.now();
  String transferStatus = '';
  Future<void> chooseRange(bool start) async {
    final now = DateTime.now(), initial = start ? from : to;
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 6)),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final hour = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (hour == null || !mounted) return;
    final value = DateTime(
      day.year,
      day.month,
      day.day,
      hour.hour,
      hour.minute,
    );
    setState(() {
      if (start) {
        from = value;
      } else {
        to = value;
      }
    });
    if (from.isAfter(to)) {
      setState(() => transferStatus = '开始时间不能晚于结束时间');
      return;
    }
    await localLogs();
  }

  Future<void> localLogs() async {
    final events = await DiagnosticLog.between(widget.api.base.host, from, to);
    if (mounted) setState(() => phoneEvents = events);
  }

  Future<void> upload() async {
    if (uploading) return;
    setState(() => uploading = true);
    try {
      if (from.isAfter(to)) throw ApiException('开始时间不能晚于结束时间');
      await DiagnosticSync(widget.api).upload(from, to);
      if (mounted) setState(() => transferStatus = '手机日志已上传到当前配对电脑');
    } catch (e) {
      if (mounted) setState(() => transferStatus = '上传失败，可恢复连接后重试：$e');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  String? time;
  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    setState(() => busy = true);
    await localLogs();
    try {
      final r = await widget.api.call('/diagnostics');
      if (mounted) {
        setState(() {
          checks = r['checks'];
          recent = r['recent'] ?? [];
          time = r['time'];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          time = DateTime.now().toIso8601String();
          checks = [
            {
              'name': '电脑连接',
              'status': '异常',
              'detail': '未取得电脑响应。请确认电脑在线、服务已启动、内置网络可用；目前无法确认根因。',
            },
            {'name': '电脑服务与助手', 'status': '未检查', 'detail': '恢复电脑连接后重新检查。'},
          ];
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded ? null : SectionAppBar(title: const Text('故障诊断')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text('日志时间段（最近 7 天）'),
        TextButton(onPressed: () => chooseRange(true), child: Text('从：$from')),
        TextButton(onPressed: () => chooseRange(false), child: Text('至：$to')),
        OutlinedButton(
          onPressed: uploading ? null : upload,
          child: Text(uploading ? '正在上传…' : '上传手机日志到当前电脑'),
        ),
        if (transferStatus.isNotEmpty) Text(transferStatus),
        const Text(
          '电脑断连时仍可导出本地日志；电脑主动获取仅在手机应用在线时响应。',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        const Text('检查当前电脑的连接与服务', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : check,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(busy ? '正在检查…' : '重新检查'),
        ),
        if (time != null)
          Text(
            '检查时间：$time',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        for (final r in checks)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(r['name'], style: const TextStyle(fontSize: 14)),
            subtitle: Text(r['status'], style: const TextStyle(fontSize: 12)),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(
                  r['detail'],
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('最近故障', style: TextStyle(fontWeight: FontWeight.w500)),
          for (final e in recent.reversed.take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${e['method']} ${e['route']}',
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(
                '${e['time']} · HTTP ${e['status']} · ${e['durationMs']} ms',
                style: const TextStyle(fontSize: 10),
              ),
            ),
        ],

        OutlinedButton.icon(
          onPressed: checks.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: jsonEncode({
                        'from': from.toUtc().toIso8601String(),
                        'to': to.toUtc().toIso8601String(),
                        'time': time,
                        'checks': checks,
                        'recent': recent,
                        'phoneEvents': phoneEvents,
                      }),
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('检查结果已复制，可粘贴反馈')),
                    );
                  }
                },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('复制诊断结果'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: checks.isEmpty
              ? null
              : () async {
                  await NativeBridge.invoke('shareDiagnostic', {
                    'text': const JsonEncoder.withIndent('  ').convert({
                      'from': from.toUtc().toIso8601String(),
                      'to': to.toUtc().toIso8601String(),
                      'time': time,
                      'checks': checks,
                      'recent': recent,
                      'phoneEvents': phoneEvents,
                    }),
                  });
                },
          icon: const Icon(Icons.share_outlined, size: 18),
          label: const Text('导出诊断记录'),
        ),
        if (phoneEvents.isNotEmpty)
          ExpansionTile(
            title: const Text('手机连接与请求记录'),
            children: [
              for (final e in phoneEvents.reversed.take(20))
                ListTile(
                  title: Text(e['route'], style: const TextStyle(fontSize: 12)),
                  subtitle: Text(
                    '${e['time']} · ${e['category']}',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
            ],
          ),
        const Text(
          '当前检查不自动修复。电脑不可达时无法检查其服务与助手；结果未包含聊天内容或账号信息。',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    ),
  );
}
