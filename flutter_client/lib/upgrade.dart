import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

bool allowedUpgradeUrl(String raw) {
  final u = Uri.tryParse(raw);
  if (u == null || u.scheme != 'https' || u.userInfo.isNotEmpty) return false;
  return [
    'chatgpt.com',
    'openai.com',
    'stripe.com',
    'auth0.com',
    'google.com',
    'apple.com',
    'microsoftonline.com',
    'live.com',
  ].any((host) => u.host == host || u.host.endsWith('.$host'));
}

class UpgradePage extends StatefulWidget {
  const UpgradePage({super.key});
  @override
  State<UpgradePage> createState() => _UpgradePageState();
}

class _UpgradePageState extends State<UpgradePage> {
  WebViewController? controller;
  String? error;
  int progress = 0;
  @override
  void initState() {
    super.initState();
    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (v) {
              if (mounted) setState(() => progress = v);
            },
            onNavigationRequest: (r) {
              if (allowedUpgradeUrl(r.url)) return NavigationDecision.navigate;
              if (r.isMainFrame && mounted) {
                setState(() => error = '该登录或支付跳转暂不支持在 App 内完成，请返回官方页面。');
              }
              return NavigationDecision.prevent;
            },
            onWebResourceError: (e) {
              if (e.isForMainFrame == true && mounted) {
                setState(() => error = '官方页面加载失败。登录和支付是否可用取决于官方对内嵌网页的支持，请重试。');
              }
            },
          ),
        )
        ..loadRequest(Uri.parse('https://chatgpt.com/#pricing'));
    } catch (_) {
      error = '当前设备暂不支持内嵌网页。';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('升级 Codex'),
      actions: [
        IconButton(
          tooltip: '重新加载',
          onPressed: controller == null
              ? null
              : () {
                  setState(() => error = null);
                  controller!.reload();
                },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'OpenAI 官方页面 · 请登录与电脑端 Codex 相同的账号。完成后返回并刷新额度。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        if (progress < 100 && controller != null)
          LinearProgressIndicator(value: progress / 100, minHeight: 2),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(error!, style: const TextStyle(fontSize: 12)),
          ),
        if (controller != null)
          Expanded(child: WebViewWidget(controller: controller!)),
      ],
    ),
  );
}
