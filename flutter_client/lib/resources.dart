import 'downloads.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'preview.dart';
import 'native.dart';

class SessionResources {
  final CollieApi api;
  final String session;
  Future<List<Json>>? _listing;
  SessionResources(this.api, this.session);
  String get root => '/local/${Uri.encodeComponent(session)}/resources';
  Future<Json?> find(String ref) async {
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

  Future<void> open(BuildContext context, String ref) async {
    try {
      final uri = Uri.tryParse(ref);
      if (uri != null && ['http', 'https'].contains(uri.scheme)) {
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw ApiException('无法打开浏览器');
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
    final file = await find(ref);
    if (file == null) throw ApiException('图片未被此会话引用');
    return Uint8List.fromList(await api.imageBytes('$root/${file['id']}'));
  }
}

class SessionImage extends StatefulWidget {
  final SessionResources resources;
  final String source;
  final String? alt;
  const SessionImage({
    super.key,
    required this.resources,
    required this.source,
    this.alt,
  });
  @override
  State<SessionImage> createState() => _SessionImageState();
}

class _SessionImageState extends State<SessionImage> {
  late Future<Uint8List> bytes;
  bool get remote =>
      ['http', 'https'].contains(Uri.tryParse(widget.source)?.scheme);
  @override
  void initState() {
    super.initState();
    if (!remote) bytes = widget.resources.image(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    Widget error() => OutlinedButton.icon(
      onPressed: () {
        if (!remote) {
          setState(() => bytes = widget.resources.image(widget.source));
        }
        widget.resources.open(context, widget.source);
      },
      icon: const Icon(Icons.broken_image_outlined),
      label: Text('${widget.alt ?? '图片'} · 点击打开或重试'),
    );
    final image = remote
        ? Image.network(
            widget.source,
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
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => error(),
              );
            },
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () => widget.resources.open(context, widget.source),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: image,
        ),
      ),
    );
  }
}
