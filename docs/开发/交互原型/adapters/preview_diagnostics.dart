import 'ui.dart' show collieSheet;

import 'package:flutter/material.dart';

Future<void> showPreviewDiagnostics(BuildContext context) async {
  await collieSheet<void>(context, '故障诊断', (_) => const PreviewDiagnostics());
}

class PreviewDiagnostics extends StatefulWidget {
  const PreviewDiagnostics({super.key});
  @override
  State<PreviewDiagnostics> createState() => _PreviewDiagnosticsState();
}

class _PreviewDiagnosticsState extends State<PreviewDiagnostics> {
  String scenario = '连接异常';
  bool checking = false;
  DateTime? checkedAt;
  Future<void> check() async {
    setState(() => checking = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() {
        checking = false;
        checkedAt = DateTime.now();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: .55);
    final rows = <(String, String, String)>[
      ('手机网络', '正常', '手机可访问网络。网络可用不代表来源电脑可达。'),
      (
        '电脑连接',
        scenario == '连接异常' ? '异常' : '正常',
        scenario == '连接异常'
            ? '模拟检查：来源电脑请求超时。尚不能判断是电脑休眠、服务停止或内置网络中断。建议确认电脑在线，再检查电脑服务。'
            : '模拟检查：已收到来源电脑响应。',
      ),
      (
        '电脑服务',
        scenario == '连接异常' ? '未检查' : '正常',
        scenario == '连接异常' ? '电脑不可达，无法检查服务状态，不能据此判断服务故障。' : '模拟检查：服务健康接口响应正常。',
      ),
      (
        'Codex 连接',
        scenario == '连接异常'
            ? '未检查'
            : scenario == '助手异常'
            ? '异常'
            : '正常',
        scenario == '助手异常'
            ? '模拟检查：助手后端连接失败。建议检查电脑上的 Codex 是否可正常使用，再重新检查。'
            : scenario == '连接异常'
            ? '需恢复电脑连接后检查。'
            : '模拟检查：助手后端响应正常。',
      ),
      (
        '文件访问',
        scenario == '连接异常'
            ? '未检查'
            : scenario == '文件异常'
            ? '异常'
            : '正常',
        scenario == '文件异常'
            ? '模拟检查：文件请求返回 404。可能是文件已移动、删除或访问被限制；仅凭状态码不能确定具体原因。建议检查原文件和服务端对应请求日志。'
            : scenario == '连接异常'
            ? '需恢复电脑连接后检查。'
            : '模拟检查：示例文件读取正常。',
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '检查当前电脑的连接与服务',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          '演示检查 · 不读取真实日志或执行修复',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: scenario,
          decoration: const InputDecoration(labelText: '模拟故障场景'),
          items: [
            for (final s in ['连接异常', '助手异常', '文件异常', '全部正常'])
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: checking
              ? null
              : (v) => setState(() {
                  scenario = v!;
                  checkedAt = null;
                }),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: checking ? null : check,
            icon: Icon(
              checking ? Icons.hourglass_top : Icons.refresh,
              size: 18,
            ),
            label: Text(checking ? '正在检查…' : '重新检查'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          checking
              ? '正在获取检查结果'
              : checkedAt == null
              ? '示例检查结果'
              : '检查时间 ${TimeOfDay.fromDateTime(checkedAt!).format(context)}',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        for (final row in rows)
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: .15),
                ),
              ),
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: Icon(
                row.$2 == '正常'
                    ? Icons.check_circle_outline
                    : row.$2 == '异常'
                    ? Icons.error_outline
                    : Icons.remove_circle_outline,
                size: 20,
                color: row.$2 == '异常' ? const Color(0xffb45b4b) : muted,
              ),
              title: Text(row.$1, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                checking ? '检查中' : row.$2,
                style: TextStyle(fontSize: 12, color: muted),
              ),
              childrenPadding: const EdgeInsets.only(left: 40, bottom: 16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    row.$3,
                    style: TextStyle(fontSize: 12, height: 1.7, color: muted),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          '最近故障',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('电脑连接超时', style: TextStyle(fontSize: 13)),
          subtitle: Text(
            '今天 19:05 · 示例记录 · 原因未确认',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('故障详情'),
              content: const Text(
                '请求电脑服务时超时，未取得服务端响应。\n\n证据：手机端请求超时（模拟）。\n缺口：电脑端、内置网络日志。\n结论：原因未确认。\n\n正式版支持按故障发生时间关联两端日志。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('导出诊断记录'),
              content: const Text(
                '正式版可选择故障时间段，导出脱敏日志与检查结果。电脑不可达时仅导出手机记录，并标明证据缺口。\n\n不包含密钥、配对码、聊天正文或附件内容。原型不生成真实诊断包。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('知道了'),
                ),
              ],
            ),
          ),
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('导出诊断记录'),
        ),
      ],
    );
  }
}
