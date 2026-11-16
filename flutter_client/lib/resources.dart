import 'dart:io';
import 'session_gallery.dart';
import 'session_video.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'offline_assets.dart';
import 'dart:convert';
import 'downloads.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'session_web.dart';
import 'api.dart';
import 'preview.dart';
import 'native.dart';

class SessionResources {
  final CollieApi api;
  final String session;
  bool offline = false;
  List<String> scopeReferences = [];
  Future<List<Json>>? _listing;
  SessionResources(this.api, this.session);
  void invalidate() => _listing = null;
  String get root => '/local/${Uri.encodeComponent(session)}/resources';
  Future<Json?> find(String ref) async {
    final embedded = RegExp(
      r'^gcollie-resource:([a-f0-9]{32})$',
    ).firstMatch(ref);
    if (embedded != null) {
      return {'id': embedded[1], 'ref': ref, 'name': '会话图片.png', 'image': true};
    }
    final hadListing = _listing != null;
    _listing ??= api
        .call(root)
        .then(
          (d) => (d['resources'] as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
        );
    try {
      final items = await _listing!;
      for (final r in items) {
        if (r['ref'] == ref ||
            Uri.tryParse(r['ref'] as String)?.toString() == ref) {
          return r;
        }
      }
      _listing = null;
      if (hadListing) return await find(ref);
      return null;
    } catch (_) {
      _listing = null;
      rethrow;
    }
  }

  Future<void> download(BuildContext context, String ref) async {
    try {
      final file = await find(ref);
      if (file == null) throw ApiException('此链接不是当前会话可下载的文件');
      final result = await api.call('$root/${file['id']}/preview', {});
      final url = await api.browserPreview(result['path'] as String);
      await NativeBridge.invoke<void>('downloadFile', {
        'url': url.resolve('./content?download=1').toString(),
        'name': file['name'] as String,
        'previewRequest': '$root/${file['id']}/preview',
        'computer': '${api.base}',
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已开始下载'),
            action: SnackBarAction(
              label: '查看',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DownloadsPage(api: api),
                ),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载未成功：$e')));
      }
    }
  }

  Future<void> gallery(BuildContext context, String ref) async {
    if (ref.startsWith('gcollie-upload:')) {
      if (context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FilePreviewPage(
              name: '待同步图片',
              url: api.base,
              image: image(ref),
              showDownload: false,
            ),
          ),
        );
      }
      return;
    }
    List<Json> items = [];
    try {
      if (!offline) {
        final result = await api.call(root);
        items = (result['resources'] as List)
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .where(
              (r) =>
                  r['image'] == true ||
                  isSessionVideo('${r['ref']}') ||
                  isSessionVideo('${r['name']}'),
            )
            .toList();
      }
      final known = items.map((r) => '${r['ref']}').toSet();
      for (final source in scopeReferences) {
        if (!isSessionVideo(source) &&
            !RegExp(
              r'\.(png|jpe?g|gif|webp)([?#].*)?$',
              caseSensitive: false,
            ).hasMatch(source) &&
            !source.startsWith('gcollie-resource:') &&
            !source.startsWith('data:image/')) {
          continue;
        }
        if (known.add(source)) {
          items.add({
            'ref': source,
            'name': isSessionVideo(source) ? '会话视频' : '会话图片',
            'image': !isSessionVideo(source),
          });
        }
      }
      final seen = <String>{};
      items = items.where((r) => seen.add('${r['ref']}')).toList();
      var selected = items.indexWhere((r) => r['ref'] == ref);
      if (selected < 0) {
        items.insert(0, {'ref': ref, 'name': '会话图片', 'image': true});
        selected = 0;
      }
      if (context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionMediaBrowser(
              resources: this,
              items: items,
              initialIndex: selected,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开会话媒体：$e')));
      }
    }
  }

  Future<void> open(BuildContext context, String ref) async {
    try {
      final cached = await OfflineAssets.read(
        OfflineAssets.key('${api.base}', session, ref),
      );
      if (cached != null && context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FilePreviewPage(
              name: '本地会话图片',
              url: api.base,
              image: Future.value(cached),
              showDownload: false,
            ),
          ),
        );
        return;
      }
      if (offline) throw ApiException('此资源尚未下载，连接电脑后可打开；已下载文件请到下载内容查看。');

      final uri = Uri.tryParse(ref);
      if (uri != null && ['http', 'https'].contains(uri.scheme)) {
        if (!sessionWebUrl(uri)) throw ApiException('不支持此链接');
        if (context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => SessionWebPage(url: uri)),
          );
        }
        return;
      }
      final file = await find(ref);
      if (file == null) throw ApiException('此链接不是当前会话可访问的文件');
      final result = await api.call('$root/${file['id']}/preview', {});
      final url = await api.browserPreview(result['path'] as String);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FilePreviewPage(
            name: file['name'] as String,
            sourceApi: api,
            previewRequest: '$root/${file['id']}/preview',
            url: url.replace(queryParameters: {'embedded': '1'}),
            image: file['image'] == true ? image(ref) : null,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<Uint8List> image(String ref) async {
    if (ref.startsWith('gcollie-upload:')) {
      final id = ref.substring('gcollie-upload:'.length);
      final local = api.attachmentPreviews[id];
      // Preview ids are bound to this API instance; only files saved by the picker.
      if (local == null ||
          local['image'] != true ||
          local['session'] != session) {
        throw ApiException('本地图片预览不可用');
      }
      return File(local['path'] as String).readAsBytes();
    }
    if (RegExp(r'^data:image/(png|jpeg|gif|webp);base64,').hasMatch(ref)) {
      if (ref.length > 8 * 1024 * 1024) throw ApiException('图片数据过大');
      return base64Decode(ref.substring(ref.indexOf(',') + 1));
    }
    final key = OfflineAssets.key('${api.base}', session, ref);
    final cached = await OfflineAssets.read(key);
    if (offline) {
      if (cached != null) return cached;
      throw ApiException('图片未缓存，连接电脑后加载');
    }
    try {
      final file = await find(ref);
      if (file == null) throw ApiException('图片未被此会话引用');
      final bytes = Uint8List.fromList(
        await api.imageBytes('$root/${file['id']}'),
      );
      unawaited(OfflineAssets.save(key, bytes).catchError((_) {}));
      return bytes;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }
}

class SessionImage extends StatefulWidget {
  final SessionResources resources;
  final String source;
  final String? alt;
  final bool inset;
  const SessionImage({
    super.key,
    required this.resources,
    required this.source,
    this.alt,
    this.inset = true,
  });
  @override
  State<SessionImage> createState() => _SessionImageState();
}

class _SessionImageState extends State<SessionImage> {
  late Future<Uint8List> bytes;
  bool failed = false;
  DateTime lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<Uint8List> load() async {
    lastAttempt = DateTime.now();
    failed = false;
    for (var attempt = 0; ; attempt++) {
      try {
        final data = await widget.resources.image(widget.source);
        failed = false;
        return data;
      } catch (_) {
        if (attempt >= 2 || !mounted) {
          failed = true;
          rethrow;
        }
        widget.resources.invalidate();
        await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
  }

  @override
  void didUpdateWidget(covariant SessionImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!remote &&
        (oldWidget.source != widget.source ||
            oldWidget.resources != widget.resources ||
            (failed &&
                DateTime.now().difference(lastAttempt).inSeconds >= 10))) {
      bytes = load();
    }
  }

  bool get remote =>
      ['http', 'https'].contains(Uri.tryParse(widget.source)?.scheme);
  @override
  void initState() {
    super.initState();
    if (!remote) bytes = load();
  }

  @override
  Widget build(BuildContext context) {
    Widget error() => OutlinedButton.icon(
      onPressed: () {
        if (!remote) {
          setState(() => bytes = load());
        }
        widget.resources.gallery(context, widget.source);
      },
      icon: const Icon(Icons.broken_image_outlined),
      label: Text('${widget.alt ?? '图片'} · 点击打开或重试'),
    );
    final image = remote
        ? Image.network(
            widget.source,
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => error(),
          )
        : FutureBuilder<Uint8List>(
            future: bytes,
            builder: (context, state) {
              if (state.hasError) return error();
              if (!state.hasData) {
                return const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Image.memory(
                state.data!,
                width: double.infinity,
                frameBuilder: (context, child, frame, synchronous) =>
                    frame != null || synchronous
                    ? child
                    : SizedBox(
                        height: MediaQuery.sizeOf(context).height * .5,
                        child: child,
                      ),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => error(),
              );
            },
          );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.inset ? 8 : 0),
      child: InkWell(
        onTap: () => widget.resources.gallery(context, widget.source),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: image,
        ),
      ),
    );
  }
}

class SessionGallery extends StatefulWidget {
  final SessionResources resources;
  final List<String> sources;
  final Set<String> videos;
  const SessionGallery({
    super.key,
    required this.resources,
    required this.sources,
    this.videos = const {},
  });
  @override
  State<SessionGallery> createState() => _SessionGalleryState();
}

class _SessionGalleryState extends State<SessionGallery> {
  String? selected;
  final thumbnails = <String, Future<Uint8List>>{};
  final ratios = <String, double>{};
  Future<Uint8List> galleryImage(String ref) =>
      thumbnails.putIfAbsent(ref, () async {
        final Uint8List bytes;
        if (widget.videos.contains(ref) || isSessionVideo(ref)) {
          final file = await widget.resources.find(ref);
          if (file == null) throw StateError('视频暂不可读');
          bytes = Uint8List.fromList(
            await widget.resources.api.imageBytes(
              '${widget.resources.root}/${file['id']}/poster',
            ),
          );
        } else {
          bytes = await widget.resources.image(ref);
        }
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final ratio = descriptor.width / descriptor.height;
        descriptor.dispose();
        buffer.dispose();
        if (mounted) setState(() => ratios[ref] = ratio);
        return bytes;
      });
  @override
  void didUpdateWidget(covariant SessionGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resources != widget.resources) {
      thumbnails.clear();
      ratios.clear();
    }
    thumbnails.removeWhere((key, value) => !widget.sources.contains(key));
    if (!widget.sources.contains(selected)) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sources.isEmpty) return const SizedBox.shrink();
    final current = selected ?? widget.sources.first;
    galleryImage(current).catchError((_) => Uint8List(0));
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(
          (constraints.maxWidth - 60) / (ratios[current] ?? 1),
          MediaQuery.sizeOf(context).height * .65,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  height: height,
                  child:
                      widget.videos.contains(current) || isSessionVideo(current)
                      ? SessionVideo(
                          key: ValueKey(current),
                          resources: widget.resources,
                          source: current,
                        )
                      : SessionImage(
                          key: ValueKey(current),
                          resources: widget.resources,
                          source: current,
                          alt: '查看选中图片',
                          inset: false,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                height: height,
                child: ListView.separated(
                  primary: false,
                  itemCount: widget.sources.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final ref = widget.sources[index];
                    return Semantics(
                      label: '选择第 ${index + 1} 张图片',
                      selected: current == ref,
                      button: true,
                      child: InkWell(
                        onTap: () => setState(() => selected = ref),
                        child: Container(
                          height: 52,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: current == ref
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade300,
                              width: current == ref ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: FutureBuilder<Uint8List>(
                              future: galleryImage(ref),
                              builder: (context, value) => value.hasData
                                  ? Image.memory(
                                      value.data!,
                                      fit: BoxFit.cover,
                                      excludeFromSemantics: true,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.broken_image_outlined,
                                        size: 18,
                                      ),
                                    )
                                  : value.hasError
                                  ? const Icon(
                                      Icons.broken_image_outlined,
                                      size: 18,
                                    )
                                  : const Center(
                                      child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
