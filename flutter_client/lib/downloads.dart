import 'connection_page.dart';
import 'api.dart';
import 'preview.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'native.dart';

class DownloadsPage extends StatefulWidget {
  final CollieApi? api;
  const DownloadsPage({super.key, this.api});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<dynamic> rows = [];
  String filter = '全部', error = '';
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await NativeBridge.invoke<List<dynamic>>('downloads');
      if (mounted) {
        setState(() {
          rows = r ?? [];
          error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => ConnectionPage(
    api: widget.api,
    appBar: AppBar(
      leading: IconButton(
        tooltip: '返回',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back, size: 23),
      ),
      title: const Text(
        '下载内容',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
      ),
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Row(
            children: [
              for (final f in ['全部', '下载中', '已完成', '失败'])
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => filter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: filter == f
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: filter == f
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: filter == f ? 1 : .5),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (error.isNotEmpty) Text(error),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: Text('还没有下载内容')),
            ),
          for (final r in rows)
            if (filter == '全部' ||
                (filter == '已完成' && r['status'] == 8) ||
                (filter == '失败' && (r['status'] == 16 || r['status'] == -1)) ||
                (filter == '下载中' && [1, 2, 4].contains(r['status'])))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: .15),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r['name'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            r['status'] == 8
                                ? '下载完成'
                                : r['status'] == 16
                                ? '下载失败（${r['reason']}），请从原会话重试'
                                : r['status'] == -1
                                ? '记录或文件已移除'
                                : '下载中 · ${r['bytes'] ?? 0} / ${r['total'] ?? 0} 字节',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                          if ([1, 2, 4].contains(r['status']))
                            const LinearProgressIndicator(),
                        ],
                      ),
                    ),
                    if (r['status'] == 16 &&
                        r['previewRequest'] != null &&
                        r['previewRequest'] != '')
                      TextButton(
                        onPressed: () async {
                          try {
                            final api = widget.api;
                            if (api == null || '${api.base}' != r['computer']) {
                              throw ApiException('请切换到来源电脑后重试');
                            }
                            final ticket = await api.call(
                              r['previewRequest'],
                              {},
                            );
                            final url = await api.browserPreview(
                              ticket['path'],
                            );
                            await NativeBridge.invoke('downloadFile', {
                              'url': url
                                  .resolve('./content?download=1')
                                  .toString(),
                              'name': r['name'],
                              'previewRequest': r['previewRequest'],
                              'computer': r['computer'],
                            });
                            await load();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        },
                        child: const Text('重试'),
                      ),
                    if (r['status'] == 8)
                      TextButton(
                        onPressed: () async {
                          try {
                            final bytes = await NativeBridge.invoke<Uint8List>(
                              'readDownloadImage',
                              {'id': r['id']},
                            );
                            if (bytes != null && context.mounted) {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => FilePreviewPage(
                                    name: r['name'],
                                    url: Uri.parse('about:blank'),
                                    image: Future.value(bytes),
                                    showDownload: false,
                                  ),
                                ),
                              );
                              return;
                            }
                            await NativeBridge.invoke('openDownload', {
                              'id': r['id'],
                            });
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        },
                        child: const Text('打开'),
                      ),
                  ],
                ),
              ),
        ],
      ),
    ),
  );
}
