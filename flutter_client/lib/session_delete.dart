import 'package:flutter/material.dart';
import 'api.dart';

/// Confirmation uses fresh server eligibility. Network uncertainty never retries a write.
class SessionDeletePanel extends StatefulWidget {
  final Json detail;
  final String computer;
  final String? blocked;
  final Future<Json> Function() eligibility;
  final Future<Json> Function(String requestId) remove;
  final Future<void> Function(List<String>) onDeleted;
  const SessionDeletePanel({
    super.key,
    required this.detail,
    required this.computer,
    this.blocked,
    required this.eligibility,
    required this.remove,
    required this.onDeleted,
  });
  @override
  State<SessionDeletePanel> createState() => _SessionDeletePanelState();
}

class _SessionDeletePanelState extends State<SessionDeletePanel> {
  Json? permission;
  String error = '';
  bool loading = true, deleting = false, uncertain = false, deleted = false;
  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final p = await widget.eligibility();
      if (mounted) {
        setState(() {
          permission = p;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '无法确认删除条件：$e';
          permission = null;
          loading = false;
        });
      }
    }
  }

  Future<void> remove() async {
    if (deleting ||
        uncertain ||
        deleted ||
        loading ||
        widget.blocked != null ||
        permission?['allowed'] != true) {
      return;
    }
    setState(() {
      deleting = true;
      error = '';
    });
    try {
      final r = await widget.remove(requestId());
      if (r['deleted'] != true || r['ok'] != true) {
        throw ApiException('电脑未确认删除结果', 0);
      }
      // Mark confirmed before local refresh so refresh errors can never repeat deletion.
      deleted = true;
      await widget.onDeleted(
        List<String>.from(r['deletedIds'] ?? [widget.detail['id']]),
      );
    } catch (e) {
      if (!mounted) return;
      final knownFailure =
          e is ApiException && e.status > 0 && e.outcome == 'failed';
      setState(() {
        deleting = false;
        uncertain = !deleted && !knownFailure;
        error = deleted
            ? '电脑已确认删除，本地列表更新失败，请刷新核对。'
            : uncertain
            ? '删除结果未知，请刷新列表核对，勿再次提交。$e'
            : '删除未完成，会话已保留。$e';
        permission = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reason =
        widget.blocked ??
        (permission?['allowed'] == true
            ? null
            : permission?['reason'] as String?);
    return PopScope(
      canPop: !deleting,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.detail['title']}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '${widget.computer} · ${widget.detail['agent']}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const Text(
            '删除后不可恢复，将移除这台电脑上的会话和历史消息（含压缩、重置历史），并撤销该会话的分享。不删除项目文件。其他已加载页面可能需刷新。',
          ),
          const SizedBox(height: 12),
          if (loading) const Text('正在检查删除条件…'),
          if (reason != null) Text(reason),
          if (error.isNotEmpty)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: deleting ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed:
                loading ||
                    deleting ||
                    uncertain ||
                    deleted ||
                    reason != null ||
                    permission?['allowed'] != true
                ? null
                : remove,
            child: Text(deleting ? '正在删除…' : '确认删除'),
          ),
          if (!loading &&
              !deleting &&
              !uncertain &&
              !deleted &&
              (error.isNotEmpty || permission == null))
            TextButton(onPressed: check, child: const Text('重新检查删除条件')),
        ],
      ),
    );
  }
}
