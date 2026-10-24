import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'reset_credits.dart';
import 'upgrade.dart';

List<Json> codexWindows(Json? account) {
  final result = <Json>[];
  for (final bucket in account?['limits'] ?? []) {
    if ('${bucket['id']}'.toLowerCase().contains('review')) continue;
    for (final w in bucket['windows'] ?? []) {
      if (w['usedPercent'] is num &&
          [300, 10080].contains(w['windowMinutes'])) {
        result.add(Map<String, dynamic>.from(w));
      }
    }
  }
  return result;
}

bool quotaExhausted(Json? account) =>
    codexWindows(account).any((w) => (w['usedPercent'] as num) >= 100);
String quotaCountdown(dynamic seconds, DateTime now) {
  if (seconds is! num) return '重置时间暂未提供';
  final minutes = DateTime.fromMillisecondsSinceEpoch(
    seconds.toInt() * 1000,
  ).difference(now).inMinutes;
  if (minutes <= 0) return '正在更新额度';
  final days = minutes ~/ 1440,
      hours = minutes % 1440 ~/ 60,
      mins = minutes % 60;
  return '${days > 0 ? '$days 天 ' : ''}${hours > 0 ? '$hours 小时 ' : ''}${mins > 0 ? '$mins 分钟' : ''}后重置';
}

class CodexQuotaNotice extends StatefulWidget {
  final CollieApi api;
  final bool readOnly, online;
  final String error;
  final ValueChanged<bool> onBlocked;
  final Future<void> Function() onRefresh;
  const CodexQuotaNotice({
    super.key,
    required this.api,
    required this.readOnly,
    required this.online,
    required this.error,
    required this.onBlocked,
    required this.onRefresh,
  });
  @override
  State<CodexQuotaNotice> createState() => _CodexQuotaNoticeState();
}

class _CodexQuotaNoticeState extends State<CodexQuotaNotice> {
  Json? account;
  Timer? timer;
  bool loading = false;
  String? loadError;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  @override
  void didUpdateWidget(covariant CodexQuotaNotice old) {
    super.didUpdateWidget(old);
    if (old.error != widget.error || (!old.online && widget.online)) {
      load(force: true);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool force = false}) async {
    if (loading || !widget.online) return;
    loading = true;
    try {
      dynamic data;
      try {
        data = await widget.api.call(
          '/usage/limits${force ? '?refresh=1' : ''}',
        );
      } on ApiException catch (e) {
        if (e.status != 404) rethrow;
        data = await widget.api.call('/usage${force ? '?refresh=1' : ''}');
      }
      if (!mounted) return;
      final value = data['codexAccount'];
      setState(() {
        account = value is Map ? Map<String, dynamic>.from(value) : null;
        loadError = null;
      });
      widget.onBlocked(quotaExhausted(account));
    } catch (_) {
      if (mounted) setState(() => loadError = '额度暂时无法更新，请稍后重试');
    } finally {
      loading = false;
    }
  }

  Widget window(Json w) {
    final remaining = (100 - (w['usedPercent'] as num)).clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          w['windowMinutes'] == 300 ? '5 小时限额' : '每周限额',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                quotaCountdown(w['resetsAt'], DateTime.now()),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            Text(
              '剩余 ${remaining.round()}%',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: remaining / 100,
            minHeight: 5,
            color: Theme.of(context).colorScheme.onSurface,
            backgroundColor: Theme.of(
              context,
            ).dividerColor.withValues(alpha: .18),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final windows = codexWindows(account);
    final explicit = RegExp(
      r'额度.*(用完|耗尽|上限)|usage.limit|rate.limit|quota',
      caseSensitive: false,
    ).hasMatch(widget.error);
    if (!quotaExhausted(account) && !explicit) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (windows.isEmpty)
            const Text(
              'Codex 额度暂不可用',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          for (final w in windows)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: window(w),
            ),
          if (windows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '未取得额度窗口和恢复时间，请刷新确认。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ResetCredits(
                  key: ValueKey(account?['accountKey']),
                  compact: true,
                  account: account,
                  api: widget.api,
                  readOnly: widget.readOnly || !widget.online,
                  onRefresh: () async {
                    await load(force: true);
                    await widget.onRefresh();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => const UpgradePage()),
                    );
                    if (mounted) await load(force: true);
                  },
                  child: const Text('升级', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            account?['resetCredits']?['availableCount'] is num
                ? '剩余 ${account!['resetCredits']['availableCount']} 次重置机会'
                : '重置机会暂未提供',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (loadError != null)
            Text(
              loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          if (loadError != null)
            TextButton(
              onPressed: loading ? null : () => load(force: true),
              child: const Text('刷新额度', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }
}
