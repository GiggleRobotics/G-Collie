import 'section_app_bar.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DiagnosticsPage extends StatefulWidget {
  final CollieApi api;
  const DiagnosticsPage({super.key, required this.api});
  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  List<dynamic> checks = [];
  List<dynamic> recent = [];
  List<dynamic> phoneEvents = [];
  bool busy = false;
  String? time;
  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    setState(() => busy = true);
    try {
      final raw = await const FlutterSecureStorage().read(
        key: 'diagnostic-failures',
      );
      phoneEvents = raw == null ? [] : jsonDecode(raw);
      phoneEvents = phoneEvents
          .where((e) => e['computer'] == widget.api.base.host)
          .toList();
    } catch (_) {}
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
    appBar: SectionAppBar(title: const Text('故障诊断')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
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
