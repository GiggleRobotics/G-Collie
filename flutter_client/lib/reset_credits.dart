import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';

class ResetCredits extends StatefulWidget {
  final Json? account;
  final CollieApi api;
  final bool readOnly;
  final bool compact;
  final String? creditId;
  final Future<void> Function() onRefresh;
  const ResetCredits({
    super.key,
    required this.account,
    required this.api,
    required this.onRefresh,
    this.readOnly = false,
    this.compact = false,
    this.creditId,
  });
  @override
  State<ResetCredits> createState() => _ResetCreditsState();
}

class _ResetCreditsState extends State<ResetCredits> {
  static const storage = FlutterSecureStorage();
  bool busy = false;
  String message = '';
  String? pendingKey;
  String? pendingCreditId;
  bool restored = false;
  String get storageKey =>
      'gcollie-reset-${base64Url.encode(utf8.encode('${widget.api.base}:${widget.account?['accountKey']}'))}';
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      final key = await storage.read(key: storageKey);
      if (mounted) {
        setState(() {
          if (key != null && key.startsWith('{')) {
            final value = jsonDecode(key);
            pendingKey = value['key'];
            pendingCreditId = value['creditId'];
          } else {
            pendingKey = key;
          }
          restored = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          message = '无法读取重置记录，请检查设备存储';
          restored = false;
        });
      }
    }
  }

  Future<void> reset() async {
    if (busy) return;
    await restore();
    if (!mounted || !restored) return;
    setState(() => busy = true);
    final account = widget.account!;
    final cards =
        ((account['resetCredits']?['credits'] as List?) ?? [])
            .where((c) => c['status'] == 'available' && c['id'] is String)
            .toList()
          ..sort(
            (a, b) => ((a['expiresAt'] as num?) ?? double.infinity).compareTo(
              (b['expiresAt'] as num?) ?? double.infinity,
            ),
          );
    String? selected = pendingKey != null
        ? pendingCreditId
        : widget.creditId ?? (cards.isEmpty ? null : cards.first['id']);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              24 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * .78,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '使用限额重置',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Text(
                      '账号：${account['accountLabel'] ?? account['accountKey']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    if (pendingKey != null)
                      const Text(
                        '上次操作结果尚未确认。重试将沿用原卡片和操作编号，不能更换卡片。',
                        style: TextStyle(fontSize: 12),
                      ),
                    for (final card in cards)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ListTile(
                          leading: Icon(
                            selected == card['id']
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          onTap: pendingKey != null
                              ? null
                              : () => change(() => selected = card['id']),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: Theme.of(
                                ctx,
                              ).dividerColor.withValues(alpha: .2),
                            ),
                          ),
                          title: Text(
                            card['title'] ?? '使用限额重置',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            '${card['description'] ?? (card['resetType'] == 'codexRateLimits' ? '每周 + 5 小时' : '范围以上游信息为准')}\n${card['expiresAt'] is num ? '到期：${DateTime.fromMillisecondsSinceEpoch((card['expiresAt'] as num).toInt() * 1000).toLocal()}' : '未提供到期时间'}',
                            style: const TextStyle(fontSize: 12, height: 1.6),
                          ),
                        ),
                      ),
                    if (cards.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          '未取得卡片明细，将由 Codex 选择下一张可用卡。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      '可用 ${account['resetCredits']?['availableCount'] ?? '未知'} 次 · 使用后会消耗一张卡，具体结果以 Codex 返回为准。',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(pendingKey != null ? '重试原重置操作' : '确认使用所选重置卡'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => busy = false);
      return;
    }
    try {
      final key = pendingKey ?? requestId();
      await storage.write(
        key: storageKey,
        value: jsonEncode({'key': key, 'creditId': selected}),
      );
      pendingCreditId = selected;
      pendingKey = key;
      final result = await widget.api.call('/usage/codex/reset', {
        'accountKey': account['accountKey'],
        'idempotencyKey': key,
        if (selected != null) 'creditId': selected,
      });
      const messages = {
        'reset': '额度已重置',
        'alreadyRedeemed': '本次重置已完成',
        'nothingToReset': '当前没有可重置的额度，未消耗重置卡',
        'noCredit': '账号暂无可用重置卡',
      };
      final text = messages[result['outcome']];
      if (text == null) throw ApiException('重置结果未知，请重试原操作');
      await storage.delete(key: storageKey);
      pendingKey = null;
      pendingCreditId = null;
      if (mounted) setState(() => message = text);
      try {
        await widget.onRefresh();
      } catch (_) {
        if (mounted) setState(() => message = '$text；最新额度读取失败，请刷新确认');
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e。结果未确认时，重试将沿用原操作编号。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.account?['resetCredits'];
    final disabledReason = !restored
        ? '正在读取重置记录；若长时间未恢复，请重新进入此页面'
        : busy
        ? '正在处理重置，请稍候'
        : widget.readOnly
        ? '当前设备或卡片不可执行重置'
        : widget.account?['accountKey'] == null
        ? (widget.account?['resetUnavailableReason'] as String? ??
              '账号标识暂时不可读，请刷新后重试')
        : summary == null
        ? '重置卡信息暂时不可读，请刷新后重试'
        : summary['availableCount'] == 0 && pendingKey == null
        ? '暂无可用重置卡'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.compact) ...[
          const SizedBox(height: 16),
          Text(
            '额度重置卡${summary == null ? '' : ' · ${summary['availableCount']} 张可用'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            summary == null
                ? '当前后端未提供重置卡信息，请刷新或更新 Codex。'
                : '使用 1 张恢复符合条件的账号额度。',
          ),
          if (widget.account?['accountLabel'] != null)
            Text('账号：${widget.account!['accountLabel']}'),
          for (final card in summary?['credits'] ?? [])
            if (card['status'] == 'available')
              Text(
                '${card['title'] ?? '额度重置卡'} · ${card['expiresAt'] == null ? '未提供到期时间' : '有效期至 ${DateTime.fromMillisecondsSinceEpoch((card['expiresAt'] as num).toInt() * 1000).toLocal()}'}',
              ),
        ],
        SizedBox(
          width: widget.compact ? double.infinity : null,
          child: OutlinedButton(
            style: widget.compact
                ? OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    disabledBackgroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .12),
                    disabledForegroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  )
                : null,
            onPressed: disabledReason == null ? reset : null,
            child: Text(
              busy
                  ? '正在重置…'
                  : widget.readOnly
                  ? (widget.compact ? '重置额度' : '只读设备不可使用')
                  : pendingKey != null
                  ? '重试原重置操作'
                  : widget.compact
                  ? '重置额度'
                  : '使用重置卡',
            ),
          ),
        ),
        if (disabledReason != null)
          Text(disabledReason, style: const TextStyle(fontSize: 12)),
        if (message.isNotEmpty) Text(message),
      ],
    );
  }
}
