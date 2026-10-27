import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'native.dart';

// The official login starts here; HTTPS redirects allow its identity providers.
bool allowedAuthorizationUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

class AuthorizationCompletion {
  bool pendingObserved = false;
  int confirmed = 0;
  bool observe(Map<String, dynamic> state) {
    final running = state['state'] == 'Running';
    final waiting = '${state['authURL'] ?? ''}'.isNotEmpty;
    if (!running || waiting) {
      pendingObserved = true;
      confirmed = 0;
      return false;
    }
    if (!pendingObserved) return false;
    return ++confirmed >= 2;
  }
}

class NetworkAuthorizationPage extends StatefulWidget {
  final Uri url;
  const NetworkAuthorizationPage({super.key, required this.url});
  @override
  State<NetworkAuthorizationPage> createState() =>
      _NetworkAuthorizationPageState();
}

class _NetworkAuthorizationPageState extends State<NetworkAuthorizationPage> {
  late final WebViewController controller;
  Timer? timer;
  bool checking = false;
  final completion = AuthorizationCompletion();
  int progress = 0;
  String error = '';
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => allowedAuthorizationUrl(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onProgress: (value) {
            if (mounted) setState(() => progress = value);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) {
              setState(() => error = '授权页面加载失败，请检查网络后重试');
            }
          },
        ),
      );
    if (widget.url.scheme == 'https' &&
        widget.url.host == 'login.tailscale.com') {
      controller.loadRequest(widget.url);
      timer = Timer.periodic(const Duration(seconds: 2), (_) => check());
    } else {
      error = '授权地址无效';
    }
  }

  Future<void> check() async {
    if (checking || !mounted) return;
    checking = true;
    try {
      final state = await NativeBridge.network('Status');
      if (completion.observe(state) && mounted) Navigator.pop(context, true);
    } catch (_) {
    } finally {
      checking = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('远程连接授权'),
      actions: [
        IconButton(
          tooltip: '重新加载',
          onPressed: () {
            setState(() => error = '');
            controller.reload();
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (progress < 100) LinearProgressIndicator(value: progress / 100),
        if (error.isNotEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text(error)),
        Expanded(child: WebViewWidget(controller: controller)),
      ],
    ),
  );
}
