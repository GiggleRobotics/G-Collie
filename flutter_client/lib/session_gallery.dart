import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'api.dart';
import 'resources.dart';
import 'session_video.dart';

/// One session-owned snapshot; never reads global downloads or another chat.
class SessionMediaBrowser extends StatefulWidget {
  final SessionResources resources;
  final List<Json> items;
  final int initialIndex;
  const SessionMediaBrowser({
    super.key,
    required this.resources,
    required this.items,
    required this.initialIndex,
  });
  @override
  State<SessionMediaBrowser> createState() => _SessionMediaBrowserState();
}

class _SessionMediaBrowserState extends State<SessionMediaBrowser> {
  final images = <String, Future<Uint8List>>{};
  late int index = widget.initialIndex;
  Future<Uint8List> load(String ref) =>
      images.putIfAbsent(ref, () => widget.resources.image(ref));
  void warm() {
    for (final i in [index - 1, index, index + 1]) {
      if (i < 0 || i >= widget.items.length) continue;
      final item = widget.items[i], ref = '${widget.items[i]['ref']}';
      if (isSessionVideo(ref) ||
          isSessionVideo('${item['name']}') ||
          ref.startsWith('http')) {
        continue;
      }
      load(ref)
          .then((bytes) {
            if (mounted) precacheImage(MemoryImage(bytes), context);
          })
          .catchError((_) {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    warm();
  }

  late final pager = PageController(initialPage: index);
  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  void move(int delta) {
    final next = index + delta;
    if (next >= 0 && next < widget.items.length) {
      pager.animateToPage(
        next,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${index + 1} / ${widget.items.length}',
        key: const ValueKey('gallery-count'),
      ),
      actions: [
        IconButton(
          tooltip: '下载当前媒体',
          onPressed: widget.resources.offline
              ? null
              : () => widget.resources.download(
                  context,
                  '${widget.items[index]['ref']}',
                ),
          icon: const Icon(Icons.download_outlined),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: PageView.builder(
            key: const ValueKey('session-gallery'),
            controller: pager,
            itemCount: widget.items.length,
            onPageChanged: (value) {
              setState(() => index = value);
              warm();
            },
            itemBuilder: (context, i) {
              final item = widget.items[i], ref = '${item['ref']}';
              if (isSessionVideo(ref) || isSessionVideo('${item['name']}')) {
                return i == index
                    ? Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SessionVideo(
                              key: ValueKey('gallery-video:$ref'),
                              resources: widget.resources,
                              source: ref,
                              showGalleryButton: false,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
              }
              final remote = Uri.tryParse(ref);
              if (remote != null && ['http', 'https'].contains(remote.scheme)) {
                if (widget.resources.offline) {
                  return const Center(child: Text('电脑离线，远程图片暂不可加载'));
                }
                return InteractiveViewer(
                  key: ValueKey('gallery-image:$ref'),
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      ref,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Text('图片暂时无法加载'),
                    ),
                  ),
                );
              }
              return FutureBuilder(
                future: load(ref),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('图片暂时无法加载'),
                          TextButton(
                            onPressed: () {
                              images.remove(ref);
                              setState(() {});
                            },
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return InteractiveViewer(
                    key: ValueKey('gallery-image:$ref'),
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              IconButton(
                tooltip: '上一个媒体',
                onPressed: index > 0 ? () => move(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${widget.items[index]['name'] ?? '会话媒体'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: '下一个媒体',
                onPressed: index + 1 < widget.items.length
                    ? () => move(1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
