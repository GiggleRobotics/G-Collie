import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'section_app_bar.dart';

bool sessionWebUrl(Uri uri) =>
    ['http', 'https'].contains(uri.scheme) &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;

class SessionWebPage extends StatefulWidget {
  final Uri url;
  const SessionWebPage({super.key, required this.url});
  @override
  State<SessionWebPage> createState() => _SessionWebPageState();
}

class _SessionWebPageState extends State<SessionWebPage> {
  WebViewController? controller;
  bool failed = false;
  int progress = 0;
  @override
  void initState() {
    super.initState();
    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (p) {
              if (mounted) setState(() => progress = p);
            },
            onNavigationRequest: (r) =>
                sessionWebUrl(Uri.tryParse(r.url) ?? Uri())
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
            onWebResourceError: (e) {
              if (mounted && e.isForMainFrame == true) {
                setState(() => failed = true);
              }
            },
          ),
        );
      if (sessionWebUrl(widget.url)) {
        controller!.loadRequest(widget.url);
      } else {
        failed = true;
      }
    } catch (_) {
      failed = true;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (controller != null && await controller!.canGoBack()) {
        await controller!.goBack();
      } else if (context.mounted) {
        Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: SectionAppBar(
        leading: IconButton(
          tooltip: '返回会话',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(widget.url.host, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '关闭网页',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          IconButton(
            tooltip: '复制链接',
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: widget.url.toString())),
            icon: const Icon(Icons.copy, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          if (progress < 100 && !failed)
            LinearProgressIndicator(value: progress / 100),
          Expanded(
            child: failed || controller == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('网页加载失败，请检查网络后重试'),
                        TextButton(
                          onPressed: () {
                            setState(() => failed = false);
                            controller?.loadRequest(widget.url);
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : WebViewWidget(controller: controller!),
          ),
        ],
      ),
    ),
  );
}
