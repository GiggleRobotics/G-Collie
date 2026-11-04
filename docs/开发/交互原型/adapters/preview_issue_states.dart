import 'status_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'section_app_bar.dart';

class PreviewIssueNotice extends StatefulWidget {
  final bool usage;
  final VoidCallback? onUsage;
  const PreviewIssueNotice({super.key, this.usage = false, this.onUsage});
  @override
  State<PreviewIssueNotice> createState() => _PreviewIssueNoticeState();
}

class _PreviewIssueNoticeState extends State<PreviewIssueNotice> {
  bool checking = false, recovered = false;
  Future<void> retry() async {
    setState(() => checking = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted)
      setState(() {
        checking = false;
        recovered = true;
      });
  }

  @override
  Widget build(BuildContext context) {
    final scenario = Uri.base.queryParameters['state'];
    if (!['quota-error', 'codex-auth', 'codex-timeout'].contains(scenario)) {
      return const SizedBox.shrink();
    }
    final auth = scenario == 'codex-auth';
    return StatusNotice(
      title: recovered ? '检查完成' : auth ? '暂时无法查询额度' : scenario == 'codex-timeout' ? 'Codex 响应超时' : '暂时无法获取额度',
      message: recovered ? '这是演示反馈，实际状态以电脑返回的结果为准。' : auth ? '额度查询认证失败，不代表聊天不可用；请重新检查。' : scenario == 'codex-timeout' ? '未能及时取得结果，请重新检查。你的草稿已保留。' : '本次没有取得额度信息，请重新检查。你的草稿已保留。',
      icon: recovered ? Icons.check_circle_outline : auth ? Icons.lock_outline : scenario == 'codex-timeout' ? Icons.schedule_outlined : Icons.info_outline,
      connection: '电脑连接正常',
      primaryLabel: recovered ? '再次检查' : '重新检查',
      onPrimary: retry,
      onSecondary: widget.usage ? null : widget.onUsage,
      badge: '演示',
      checking: checking,
    );
  }
}

class PreviewLinkPage extends StatelessWidget {
  final Uri url;
  const PreviewLinkPage({super.key, required this.url});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: SectionAppBar(
      title: Text(url.host, overflow: TextOverflow.ellipsis),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          '会话链接',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        SelectableText(url.toString()),
        const SizedBox(height: 24),
        const Text('App 内网页交互演示。正式版在此使用 WebView 加载网页，返回后保留会话位置和草稿。此原型不加载外部网页。'),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url.toString()));
            if (context.mounted)
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('链接已复制')));
          },
          child: const Text('复制链接'),
        ),
        const SizedBox(height: 12),
        const Text(
          '加载失败时提供重试和复制链接；不自动跳转外部浏览器。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    ),
  );
}
