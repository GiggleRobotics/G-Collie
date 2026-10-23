import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';

class ResetCredits extends StatefulWidget {
  final Json? account;
  final CollieApi api;
  final bool readOnly;
  final Future<void> Function() onRefresh;
  const ResetCredits({
    super.key,
    required this.account,
    required this.api,
    required this.onRefresh,
    this.readOnly = false,
  });
  @override
  State<ResetCredits> createState() => _ResetCreditsState();
}

class _ResetCreditsState extends State<ResetCredits> {
  static const storage = FlutterSecureStorage();
  bool busy = false;
  String message = '';
  String? pendingKey;
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
      if (mounted) setState(() => pendingKey = key);
    } catch (_) {
      if (mounted) setState(() => message = '无法读取重置记录，请检查设备存储');
    }
  }

  Future<void> reset() async {
    if (busy) return;
    setState(() => busy = true);
    final account = widget.account!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用 1 张重置卡？'),
        content: Text(
          '账号：${account['accountLabel'] ?? account['accountKey']}\n\n服务端将选择下一张可用卡。卡片使用后将被消耗；恢复范围和下次恢复时间以服务端结果为准。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('使用 1 张并重置'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => busy = false);
      return;
    }
    try {
      final key = await storage.read(key: storageKey) ?? requestId();
      await storage.write(key: storageKey, value: key);
      pendingKey = key;
      final result = await widget.api.call('/usage/codex/reset', {
        'accountKey': account['accountKey'],
        'idempotencyKey': key,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          '额度重置卡${summary == null ? '' : ' · ${summary['availableCount']} 张可用'}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          summary == null ? '当前后端未提供重置卡信息，请刷新或更新 Codex。' : '使用 1 张恢复符合条件的账号额度。',
        ),
        if (widget.account?['accountLabel'] != null)
          Text('账号：${widget.account!['accountLabel']}'),
        for (final card in summary?['credits'] ?? [])
          if (card['status'] == 'available')
            Text(
              '${card['title'] ?? '额度重置卡'} · ${card['expiresAt'] == null ? '未提供到期时间' : '有效期至 ${DateTime.fromMillisecondsSinceEpoch((card['expiresAt'] as num).toInt() * 1000).toLocal()}'}',
            ),
        OutlinedButton(
          onPressed:
              busy ||
                  widget.readOnly ||
                  widget.account?['accountKey'] == null ||
                  summary == null ||
                  (summary['availableCount'] == 0 && pendingKey == null)
              ? null
              : reset,
          child: Text(
            busy
                ? '正在重置…'
                : widget.readOnly
                ? '只读设备不可使用'
                : pendingKey != null
                ? '重试原重置操作'
                : '使用重置卡',
          ),
        ),
        if (message.isNotEmpty) Text(message),
      ],
    );
  }
}
