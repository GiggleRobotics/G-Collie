import 'section_app_bar.dart';
import 'connection_page.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

String previewWorkspaceName = '我的工作台';
Uint8List? previewAvatar;

Widget workspaceAvatar({double size = 40}) => ClipOval(
  child: previewAvatar == null
      ? Image.asset(
          'assets/collie-mark-v2.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.pets),
        )
      : Image.memory(
          previewAvatar!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.pets),
        ),
);

Future<void> editPreviewWorkspace(
  BuildContext context, {
  bool first = false,
}) async {
  final name = TextEditingController(text: previewWorkspaceName);
  Uint8List? avatar = previewAvatar;
  String error = '';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, change) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                first ? '设置你的工作台' : '工作台资料',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              ClipOval(
                child: avatar == null
                    ? Image.asset(
                        'assets/collie-mark-v2.png',
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      )
                    : Image.memory(
                        avatar!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: () async {
                      final file = await openFile(
                        acceptedTypeGroups: [
                          const XTypeGroup(
                            label: '头像',
                            extensions: ['png', 'jpg', 'jpeg', 'webp'],
                          ),
                        ],
                      );
                      if (file == null) return;
                      final bytes = await file.readAsBytes();
                      if (!ctx.mounted) return;
                      change(() {
                        if (bytes.length > 5 * 1024 * 1024) {
                          error = '请选择不超过 5 MB 的图片';
                        } else {
                          avatar = bytes;
                          error = '';
                        }
                      });
                    },
                    child: const Text('更换头像'),
                  ),
                  TextButton(
                    onPressed: () => change(() => avatar = null),
                    child: const Text('恢复默认'),
                  ),
                ],
              ),
              TextField(
                controller: name,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '工作台名称',
                  hintText: '我的工作台',
                ),
              ),
              if (error.isNotEmpty)
                Text(error, style: const TextStyle(color: Colors.red)),
              const Text(
                '原型资料仅在本次演示中保留；头像展示圆形居中裁切效果，精细裁剪待设计。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(first ? '暂时跳过' : '取消'),
                    ),
                  ),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        previewWorkspaceName = name.text.trim().isEmpty
                            ? '我的工作台'
                            : name.text.trim();
                        previewAvatar = avatar;
                        Navigator.pop(ctx);
                      },
                      child: Text(first ? '进入工作台' : '保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  // Let the closing route release its text field before disposing its controller.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  name.dispose();
}

Future<void> showPreviewDownloads(BuildContext context) => Navigator.of(context)
    .push<void>(MaterialPageRoute(builder: (_) => const PreviewDownloads()));

class PreviewDownloads extends StatefulWidget {
  const PreviewDownloads({super.key});
  @override
  State<PreviewDownloads> createState() => _PreviewDownloadsState();
}

class _PreviewDownloadsState extends State<PreviewDownloads> {
  bool retrying = false;
  String filter = '全部';

  void openImage() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: SectionAppBar(primary: false, title: const Text('桌面截图.png')),
        body: SizedBox.expand(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 8,
            child: Image.asset(
              'assets/collie-companion-v2.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    ),
  );

  Widget fileRow({
    required IconData icon,
    required String name,
    required String meta,
    String? source,
    String? action,
    VoidCallback? onTap,
    double? progress,
    bool failed = false,
  }) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: .55);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: .15)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 22,
              color: theme.colorScheme.onSurface.withValues(alpha: .7),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  meta,
                  style: TextStyle(
                    fontSize: 12,
                    color: failed ? const Color(0xffb45b4b) : muted,
                  ),
                ),
                if (source != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
                if (progress != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      color: theme.colorScheme.onSurface,
                      backgroundColor: theme.colorScheme.onSurface.withValues(
                        alpha: .08,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            SizedBox(
              height: 34,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  side: BorderSide(
                    color: theme.dividerColor.withValues(alpha: .25),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onTap,
                child: Text(action, style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: .5);
    return ConnectionPage(
      appBar: SectionAppBar(
        primary: false,
        title: const Text(
          '下载内容',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        actions: [
          IconButton(
            tooltip: '下载说明',
            icon: const Icon(Icons.info_outline, size: 20),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('下载内容'),
                content: const Text(
                  '这里是原型演示记录，不读取手机文件或执行真实下载。正式版下载完成后可直接查看本地文件，电脑离线也能打开；重新下载需要来源电脑在线。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
        children: [
          Row(
            children: [
              for (final value in ['全部', '下载中', '已完成', '失败'])
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => filter = value),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 2,
                            color: filter == value
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: filter == value
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: filter == value ? 1 : .5),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text('今天', style: TextStyle(fontSize: 12, color: muted)),
          if (filter == '全部' || filter == '已完成')
            fileRow(
              icon: Icons.image_outlined,
              name: '桌面截图.png',
              meta: '1.6 MB · 19:12',
              source: '查看 ZZ 程序启动方式',
              action: '打开',
              onTap: openImage,
            ),
          if (filter == '全部' || filter == '下载中')
            fileRow(
              icon: Icons.folder_zip_outlined,
              name: '诊断日志.zip',
              meta: '下载中 · 8 / 20 MB',
              progress: .4,
            ),
          if (filter == '全部' || filter == '失败')
            fileRow(
              icon: Icons.picture_as_pdf_outlined,
              name: '项目报告.pdf',
              meta: retrying ? '等待来源电脑连接…' : '下载失败 · 电脑连接中断',
              failed: !retrying,
              action: retrying ? '等待中' : '重试',
              onTap: retrying ? null : () => setState(() => retrying = true),
            ),
          if (filter == '全部' || filter == '已完成') ...[
            const SizedBox(height: 28),
            Text('昨天', style: TextStyle(fontSize: 12, color: muted)),
            fileRow(
              icon: Icons.insert_drive_file_outlined,
              name: '项目资料.bin',
              meta: '256 KB · 16:40',
              action: '打开',
              onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('使用其他应用打开'),
                  content: const Text('该格式需要其他应用查看。正式版将打开手机系统应用选择器。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            '演示数据',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: muted),
          ),
        ],
      ),
    );
  }
}
