import 'package:flutter/material.dart';
import 'api.dart';
import 'quota_notice.dart';
import 'reset_credits.dart';

class AccountLimits extends StatefulWidget {
  final Json? account;
  final CollieApi api;
  final bool readOnly;
  final Future<void> Function() onRefresh;
  const AccountLimits({
    super.key,
    required this.account,
    required this.api,
    required this.readOnly,
    required this.onRefresh,
  });
  @override
  State<AccountLimits> createState() => _AccountLimitsState();
}

class _AccountLimitsState extends State<AccountLimits> {
  bool expanded = true;
  String time(dynamic value) {
    if (value is! num) return '重置时间暂未提供';
    final d = DateTime.fromMillisecondsSinceEpoch(
      value.toInt() * 1000,
    ).toLocal();
    return '将于 ${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} 重置';
  }

  @override
  Widget build(BuildContext context) {
    final windows = codexWindows(widget.account);
    final summary = widget.account?['resetCredits'];
    final cards = (summary?['credits'] as List?) ?? [];
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .16),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Codex 账号额度',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (widget.account?['limitsError'] != null) ...[
          Text(
            widget.account?['limitsErrorCode'] == 'auth_expired'
                ? '额度查询认证失败，当前额度未知；不代表聊天登录失效'
                : '电脑已连接，额度查询失败，当前额度未知',
          ),
          TextButton(onPressed: widget.onRefresh, child: const Text('刷新额度')),
        ],
        Container(
          decoration: decoration,
          child: Column(
            children: [
              if (windows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('账号暂未提供额度窗口'),
                ),
              for (final w in windows)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              w['windowMinutes'] == 300 ? '5 小时使用限额' : '每周使用限额',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              time(w['resetsAt']),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value:
                                (100 - (w['usedPercent'] as num)).clamp(
                                  0,
                                  100,
                                ) /
                                100,
                            minHeight: 6,
                            color: Theme.of(context).colorScheme.onSurface,
                            backgroundColor: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: .18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '剩余 ${(100 - (w['usedPercent'] as num)).clamp(0, 100).round()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: decoration,
          child: Column(
            children: [
              ListTile(
                title: const Text('使用限额重置', style: TextStyle(fontSize: 13)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '可用 ${summary?['availableCount'] ?? '未知'} 次',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                    ),
                  ],
                ),
                onTap: () => setState(() => expanded = !expanded),
              ),
              if (expanded) ...[
                if (cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      summary?['credits'] == null ? '未取得卡片明细' : '暂无可用重置卡',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                for (final card in cards)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          card['title'] ?? '使用限额重置',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          card['description'] ??
                              (card['resetType'] == 'codexRateLimits'
                                  ? '完全重置（每周 + 5 小时）'
                                  : '范围以上游为准'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          card['expiresAt'] is num
                              ? '到期：${DateTime.fromMillisecondsSinceEpoch((card['expiresAt'] as num).toInt() * 1000).toLocal()}'
                              : '未提供到期时间',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ResetCredits(
                          key: ValueKey(
                            '${widget.account?['accountKey']}:${card['id']}',
                          ),
                          account: widget.account,
                          api: widget.api,
                          compact: true,
                          creditId: card['id'],
                          readOnly:
                              widget.readOnly || card['status'] != 'available',
                          onRefresh: widget.onRefresh,
                        ),
                      ],
                    ),
                  ),
                if (cards.isEmpty && summary != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ResetCredits(
                      account: widget.account,
                      api: widget.api,
                      compact: true,
                      readOnly: widget.readOnly,
                      onRefresh: widget.onRefresh,
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
