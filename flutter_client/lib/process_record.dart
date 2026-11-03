import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';

String processDuration(dynamic value) {
  if (value is! num || value <= 0) return '';
  final seconds = (value / 1000).round();
  if (seconds < 1) return '不到 1 秒';
  if (seconds < 60) return '$seconds 秒';
  return '${seconds ~/ 60} 分 ${seconds % 60} 秒';
}

class ProcessRecord extends StatefulWidget {
  final Json record;
  final bool live;
  const ProcessRecord({super.key, required this.record, this.live = false});
  @override
  State<ProcessRecord> createState() => _ProcessRecordState();
}

class _ProcessRecordState extends State<ProcessRecord> {
  bool expanded = false;
  String get command {
    final commands = widget.record['commands'] as List? ?? [];
    final input = commands.isNotEmpty
        ? commands.first['command']
        : widget.record['input'];
    return '${input ?? ''}'.trim().split('\n').first;
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.record;
    final thought = e['role'] == 'reasoning';
    final status = '${e['status'] ?? 'completed'}';
    final pending = status == 'pending';
    final failed = status == 'failed';
    final commands = e['commands'] as List? ?? [];
    final duration = processDuration(e['durationMs']);
    final name = '${e['name'] ?? '工具'}';
    final verb = failed
        ? '执行失败'
        : pending
        ? (widget.live ? '正在运行' : '结果未记录')
        : status == 'submitted'
        ? '已提交'
        : '已运行';
    final description = thought
        ? '思考摘要'
        : commands.length > 1
        ? '$verb ${commands.length} 条命令 · $command'
        : '$verb ${command.isEmpty ? name : command}';
    final muted = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xffaaaaaa)
        : const Color(0xff818181);
    final detail = <String>[
      if (commands.isNotEmpty)
        for (var i = 0; i < commands.length; i++)
          '命令 ${i + 1}\n${commands[i]['command']}\n${commands[i]['exitCode'] == null ? '' : '退出码：${commands[i]['exitCode']}\n'}${commands[i]['output'] ?? ''}',
      if (commands.isEmpty && '${e['input'] ?? ''}'.isNotEmpty)
        '输入\n${e['input']}',
      if (commands.isEmpty && '${e['text'] ?? ''}'.isNotEmpty)
        '${thought ? '' : '输出\n'}${e['text']}',
    ].join('\n\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => expanded = !expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(
                    thought
                        ? Icons.lightbulb_outline
                        : failed
                        ? Icons.error_outline
                        : Icons.terminal,
                    size: 14,
                    color: failed ? const Color(0xffb66350) : muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.4, color: muted),
                    ),
                  ),
                  if (duration.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        duration,
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                  const SizedBox(width: 5),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '复制工具记录',
                icon: const Icon(Icons.copy_outlined, size: 16),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: detail));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('工具记录已复制')));
                  }
                },
              ),
            ),
          if (expanded)
            Container(
              margin: const EdgeInsets.only(left: 21, top: 3, bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xff272727)
                    : const Color(0xfff6f6f6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: SelectableText(
                    detail.isEmpty ? '暂无详细记录' : detail,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      fontFamily: thought ? null : 'monospace',
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
