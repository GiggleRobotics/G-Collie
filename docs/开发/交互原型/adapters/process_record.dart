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
        ? (pending && widget.live ? '正在思考' : '已思考')
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
    final canExpand = !thought || detail.trim().isNotEmpty;
    final showDetail = expanded && canExpand;
    final detailLines = detail.split('\n');
    final detailHeading = thought ? '思考详情' : detailLines.first;
    final detailBody = thought ? detail : detailLines.skip(1).join('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: canExpand
                ? () => setState(() => expanded = !expanded)
                : null,
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
                  if (canExpand) const SizedBox(width: 5),
                  if (canExpand)
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
          if (showDetail)
            Container(
              margin: const EdgeInsets.only(right: 21, top: 3, bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xff272727)
                    : const Color(0xfff6f6f6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          detailHeading.isEmpty ? '工具记录' : detailHeading,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          tooltip: '复制工具记录',
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: detail),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('工具记录已复制')),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        detailBody.isEmpty ? '暂无详细记录' : detailBody,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          fontFamily: thought ? null : 'monospace',
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
