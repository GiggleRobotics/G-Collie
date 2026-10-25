import 'api.dart';
import 'downloads.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'native.dart';

class FilePreviewPage extends StatefulWidget {
  final String name;
  final Uri url;
  final Future<Uint8List>? image;
  final bool showDownload;
  final CollieApi? sourceApi;
  final String? previewRequest;
  const FilePreviewPage({
    super.key,
    required this.name,
    required this.url,
    this.image,
    this.showDownload = true,
    this.sourceApi,
    this.previewRequest,
  });
  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  WebViewController? controller;
  String error = '';
  int progress = 0;
  bool downloading = false;
  final imageTransform = TransformationController();
  Offset doubleTapPosition = Offset.zero;

  @override
  void dispose() {
    imageTransform.dispose();
    super.dispose();
  }

  void toggleImageZoom() {
    if (imageTransform.value.getMaxScaleOnAxis() > 1) {
      imageTransform.value = Matrix4.identity();
    } else {
      final point = doubleTapPosition;
      imageTransform.value = Matrix4.identity()
        ..translateByDouble(-point.dx * 2, -point.dy * 2, 0, 1)
        ..scaleByDouble(3, 3, 1, 1);
    }
  }

  Uri get downloadUrl => widget.url.resolve('./content?download=1');
  @override
  void initState() {
    super.initState();
    if (widget.image == null) {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xfff1f3f2))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (value) {
              if (mounted) setState(() => progress = value);
            },
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              if (uri == null ||
                  !['http', 'https'].contains(uri.scheme) ||
                  uri.origin != widget.url.origin) {
                return NavigationDecision.prevent;
              }
              if (uri.queryParameters['download'] == '1') {
                download();
                return NavigationDecision.prevent;
              }
              return uri.path.startsWith(widget.url.resolve('.').path)
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            },
            onWebResourceError: (e) {
              if (e.isForMainFrame == true && mounted) {
                setState(() => error = '文件加载失败，请检查电脑连接后重试。');
              }
            },
          ),
        )
        ..loadRequest(widget.url);
    }
  }

  Future<void> download() async {
    if (downloading) return;
    setState(() => downloading = true);
    try {
      await NativeBridge.invoke<void>('downloadFile', {
        'url': downloadUrl.toString(),
        'name': widget.name,
        'previewRequest': widget.previewRequest ?? '',
        'computer': widget.sourceApi?.base.toString() ?? '',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已开始下载'),
            action: SnackBarAction(
              label: '查看',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DownloadsPage(api: widget.sourceApi),
                ),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载未成功：$e')));
      }
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    appBar: AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 62,
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 48,
      titleSpacing: 4,
      title: Tooltip(
        message: widget.name,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xff25332c),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              widget.image != null ? '图片查看' : '文档预览',
              style: const TextStyle(fontSize: 11, color: Color(0xff7a837e)),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.showDownload)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: .06),
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                minimumSize: const Size(38, 38),
              ),
              tooltip: '下载原文件',
              onPressed: downloading ? null : download,
              icon: const Icon(Icons.download_outlined, size: 21),
            ),
          ),
      ],
    ),
    body: widget.image != null
        ? FutureBuilder<Uint8List>(
            future: widget.image,
            builder: (context, state) {
              if (state.hasError) {
                return const Center(child: Text('图片加载失败，请返回重试。'));
              }
              if (!state.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return SizedBox.expand(
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTapDown: (details) =>
                        doubleTapPosition = details.localPosition,
                    onDoubleTap: toggleImageZoom,
                    child: InteractiveViewer(
                      transformationController: imageTransform,
                      minScale: 1,
                      maxScale: 8,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: Image.memory(state.data!, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              );
            },
          )
        : Column(
            children: [
              if (progress < 100)
                LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 2,
                  color: Theme.of(context).colorScheme.onSurface,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .06),
                ),
              if (error.isNotEmpty)
                MaterialBanner(
                  content: Text(error),
                  actions: [
                    TextButton(
                      onPressed: () {
                        setState(() => error = '');
                        controller!.reload();
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              Expanded(child: WebViewWidget(controller: controller!)),
            ],
          ),
  );
}
