import 'package:flutter/material.dart';

import 'api.dart';

class PreviewUsageLimits extends StatefulWidget {
  final CollieApi api;
  final bool readOnly;
  final Future<void> Function() onRefresh;
  const PreviewUsageLimits({
    super.key,
    required this.api,
    required this.readOnly,
    required this.onRefresh,
  });
  @override
  State<PreviewUsageLimits> createState() => _PreviewUsageLimitsState();
}

class _PreviewUsageLimitsState extends State<PreviewUsageLimits> {
  bool expanded = true;
  Set<int> get used => widget.api.previewUsedResetCards;
  Future<void> reset(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用这次重置？'),
        content: const Text('完全重置每周和 5 小时使用限额。\n\n此处仅演示，不消耗真实账户的重置机会。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('使用重置'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        used.contains(index) ||
        widget.api.credits <= 0)
      return;
    setState(() {
      used.add(index);
      widget.api.credits--;
    });
    await widget.onRefresh();
  }

  Widget limit(String title, String reset, double remaining) => Padding(
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (ctx, c) => Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 5),
                Text(
                  reset,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: remaining,
                minHeight: 6,
                color: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(context).dividerColor
                    .withValues(alpha: .18),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '剩余 ${(remaining * 100).round()}%',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    ),
  );
  BoxDecoration get box => BoxDecoration(
    border: Border.all(
      color: Theme.of(context).dividerColor.withValues(alpha: .16),
    ),
    borderRadius: BorderRadius.circular(18),
  );
  Widget get line => Divider(
    height: 1,
    color: Theme.of(context).dividerColor.withValues(alpha: .13),
  );
  @override
  Widget build(BuildContext context) {
    final exhausted =
        Uri.base.queryParameters['state'] == 'quota' && used.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Codex 账号额度',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          '账号共享额度 · 演示数据',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: box,
          child: Column(
            children: [
              limit(
                '5 小时使用限额',
                '将于 20:01 重置',
                used.isNotEmpty
                    ? 1
                    : exhausted
                    ? 0
                    : .48,
              ),
              line,
              limit('每周使用限额', '将于 10月31日 重置', used.isNotEmpty ? 1 : .76),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: box,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() => expanded = !expanded),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('使用限额重置', style: TextStyle(fontSize: 13)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xffd9f3e6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '可用 ${widget.api.credits} 次',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xff216957),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 20,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                for (final i in [0, 1]) ...[
                  if (i > 0) line,
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '完全重置（每周 + 5 小时）',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '将于 ${i == 0 ? '10/30 08:31' : '11/7 06:50'} 到期',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .onSurface,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .surface,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size(0, 32),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed:
                              widget.readOnly ||
                                  used.contains(i) ||
                                  widget.api.credits <= 0
                              ? null
                              : () => reset(i),
                          child: Text(
                            used.contains(i) ? '已使用' : '使用重置',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    '到期时间为本地时间（GMT+08:00）· 仅为原型演示',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
