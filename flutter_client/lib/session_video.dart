import 'package:flutter/foundation.dart';
import 'video_browser_stub.dart'
    if (dart.library.js_interop) 'video_browser_web.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'resources.dart';

bool isSessionVideo(String ref) => RegExp(
  r'\.(mp4|mov|m4v|webm)(?:[?#].*)?$',
  caseSensitive: false,
).hasMatch(ref);

class SessionVideo extends StatefulWidget {
  final SessionResources resources;
  final String source;
  const SessionVideo({
    super.key,
    required this.resources,
    required this.source,
  });
  @override
  State<SessionVideo> createState() => _SessionVideoState();
}

class _SessionVideoState extends State<SessionVideo> {
  WebViewController? controller;
  Uri? browserUrl;
  double aspectRatio = 16 / 9;
  bool loading = false;
  String error = '';
  Future<Uint8List?>? poster;
  bool wasOffline = false;
  @override
  void didUpdateWidget(covariant SessionVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (wasOffline && !widget.resources.offline) poster = loadPoster();
    wasOffline = widget.resources.offline;
  }

  @override
  void initState() {
    super.initState();
    wasOffline = widget.resources.offline;
    poster = loadPoster();
  }

  Future<Uint8List?> loadPoster() async {
    try {
      if (widget.resources.offline) return null;
      final remote = Uri.tryParse(widget.source);
      if (remote != null && ['http', 'https'].contains(remote.scheme)) {
        return null;
      }
      final file = await widget.resources.find(widget.source);
      if (file == null) return null;
      final bytes = Uint8List.fromList(
        await widget.resources.api.imageBytes(
          '${widget.resources.root}/${file['id']}/poster',
        ),
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (mounted) setState(() => aspectRatio = ratio);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> play() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      if (widget.resources.offline) throw StateError('电脑离线，未缓存的视频暂不可播放');
      var uri = Uri.tryParse(widget.source);
      final remote = uri != null && ['http', 'https'].contains(uri.scheme);
      if (!remote) {
        final file = await widget.resources.find(widget.source);
        if (file == null) throw StateError('视频不存在或未被当前会话引用');
        final result = await widget.resources.api.call(
          '${widget.resources.root}/${file['id']}/preview',
          {},
        );
        uri = await widget.resources.api.browserPreview(
          result['path'] as String,
        );
        uri = uri.replace(queryParameters: {'embedded': '1', 'autoplay': '1'});
      }
      if (kIsWeb) {
        if (mounted) setState(() => browserUrl = uri);
        return;
      }
      final player = WebViewController()
        ..setBackgroundColor(Colors.black)
        ..setJavaScriptMode(JavaScriptMode.unrestricted);
      if (player.platform is AndroidWebViewController) {
        await (player.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }
      player.addJavaScriptChannel(
        'VideoSize',
        onMessageReceived: (message) {
          final ratio = double.tryParse(message.message);
          if (mounted && ratio != null && ratio.isFinite && ratio > 0) {
            setState(() => aspectRatio = ratio);
          }
        },
      );
      player.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            await player.runJavaScript(
              "const v=document.querySelector('video');if(v){const size=()=>{if(v.videoWidth&&v.videoHeight)VideoSize.postMessage(String(v.videoWidth/v.videoHeight));};v.addEventListener('loadedmetadata',size);size();v.play().catch(()=>{});}",
            );
          },
          onNavigationRequest: (r) =>
              r.url == uri.toString() || r.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (e) {
            if (mounted && e.isForMainFrame == true) {
              setState(() => error = '视频加载失败，请重试或打开播放器');
            }
          },
        ),
      );
      if (remote) {
        final src = const HtmlEscape().convert(uri.toString());
        await player.loadHtmlString(
          '<html><meta name="viewport" content="width=device-width,initial-scale=1"><body style="margin:0;background:#111;color:white"><video controls autoplay playsinline preload="metadata" src="$src" style="width:100%;height:100vh" onerror="document.getElementById(\'error\').hidden=false"></video><p id="error" hidden>视频加载失败或格式暂不支持，请重试。</p></body></html>',
        );
      } else {
        await player.loadRequest(uri);
      }
      if (mounted) setState(() => controller = player);
    } catch (_) {
      if (mounted) setState(() => error = '视频暂不可播放，请检查电脑连接、文件及格式后重试');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> fullscreen() async {
    if (kIsWeb) {
      if (browserUrl == null) await play();
      if (mounted && browserUrl != null) {
        await WidgetsBinding.instance.endOfFrame;
        pauseBrowserVideos();
        if (!mounted) return;
        final url = browserUrl!;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('视频')),
              body: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: browserVideo(url),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    } else {
      await widget.resources.open(context, widget.source);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (browserUrl != null)
                  browserVideo(browserUrl!)
                else if (controller != null && error.isEmpty)
                  WebViewWidget(controller: controller!)
                else
                  FutureBuilder<Uint8List?>(
                    future: poster,
                    builder: (context, snapshot) => Material(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: InkWell(
                        onTap: loading ? null : play,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (snapshot.data != null)
                              Image.memory(snapshot.data!, fit: BoxFit.contain),
                            if (snapshot.data != null)
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Color(0x55000000),
                                    ],
                                  ),
                                ),
                              ),
                            Center(
                              child: loading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : Container(
                                      width: 52,
                                      height: 52,
                                      decoration: const BoxDecoration(
                                        color: Color(0x99000000),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 34,
                                      ),
                                    ),
                            ),
                            if (snapshot.data == null &&
                                snapshot.connectionState ==
                                    ConnectionState.waiting)
                              const Positioned(
                                left: 12,
                                bottom: 10,
                                child: Text(
                                  '正在加载封面…',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: '全屏播放',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x99000000),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.fullscreen, size: 22),
                    onPressed: fullscreen,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(error, style: const TextStyle(fontSize: 12)),
              ),
              TextButton(onPressed: play, child: const Text('重试')),
            ],
          ),
      ],
    ),
  );
}

Set<String> sessionVideoReferences(String text) {
  final result = <String>{};
  final links = RegExp(r'(?<!!)\[([^\]]*)\]\(\s*(<[^>]+>|[^\n]*?)\s*\)');
  for (final match in links.allMatches(text)) {
    var ref = match[2]!.trim();
    if (ref.startsWith('<') && ref.endsWith('>')) {
      ref = ref.substring(1, ref.length - 1);
    } else {
      ref = ref.replaceFirst(RegExp(r'\s+"[^"]*"$'), '');
    }
    if (isSessionVideo(ref) || isSessionVideo(match[1]!)) result.add(ref);
  }
  for (final match in RegExp(
    r'^MEDIA:[ \t]*(.+)$',
    multiLine: true,
  ).allMatches(text)) {
    final ref = match[1]!.trim().replaceAll(RegExp(r'^"|"$'), '');
    if (isSessionVideo(ref)) result.add(ref);
  }
  return result;
}
