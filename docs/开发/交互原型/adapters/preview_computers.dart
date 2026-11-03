import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Only demo computer metadata is persisted. No real pairing or credentials.
final previewComputers = PreviewComputers();

class PreviewComputers extends ChangeNotifier {
  final storage = const FlutterSecureStorage();
  List<Map<String, dynamic>> computers = [
    {
      'id': 'desktop',
      'name': '工作电脑',
      'address': 'http://preview.invalid',
      'online': true,
    },
  ];
  String selected = 'desktop';
  bool connecting = false;
  String? persistenceError;
  Map<String, dynamic> get current =>
      computers.firstWhere((c) => c['id'] == selected);
  Future<void> restore() async {
    try {
      final raw = await storage.read(key: 'preview-computers-v1');
      if (raw != null) {
        final saved = jsonDecode(raw);
        final rows = (saved['computers'] as List)
            .map((c) => Map<String, dynamic>.from(c))
            .toList();
        if (rows.isNotEmpty && rows.any((c) => c['id'] == saved['selected'])) {
          computers = rows;
          selected = saved['selected'];
        }
      }
    } catch (_) {
      persistenceError = '浏览器未允许保存，关闭后可能需要重新选择演示电脑';
    }
    if (Uri.base.queryParameters['state'] == 'offline')
      current['online'] = false;
    connecting = Uri.base.queryParameters['state'] == 'reconnecting';
    if (connecting) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        connecting = false;
        current['online'] = true;
        notifyListeners();
      });
    }
  }

  Future<void> save() async {
    try {
      await storage.write(
        key: 'preview-computers-v1',
        value: jsonEncode({'selected': selected, 'computers': computers}),
      );
    } catch (_) {
      persistenceError = '演示电脑信息未能保存，刷新后可能恢复默认状态';
    }
  }

  Future<void> choose(String id) async {
    selected = id;
    connecting = false;
    await save();
    notifyListeners();
  }

  Future<void> retry() async {
    if (connecting) return;
    final id = selected;
    connecting = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(seconds: 2));
    if (selected != id) return;
    connecting = false;
    current['online'] = true;
    await save();
    notifyListeners();
  }
}

Future<void> showPreviewComputers(
  BuildContext context,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * .82,
  ),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (ctx) => AnimatedBuilder(
    animation: previewComputers,
    builder: (ctx, _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '电脑与连接',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '关闭电脑管理',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '选择要查看的电脑，切换不会停止其他电脑上的任务。',
              style: TextStyle(fontSize: 12, height: 1.6, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final c in previewComputers.computers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: Theme.of(ctx).colorScheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: c['id'] == previewComputers.selected
                                  ? Theme.of(ctx).colorScheme.onSurface
                                  : Theme.of(ctx).dividerColor
                                        .withValues(alpha: .2),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: const Icon(Icons.computer_outlined),
                            title: Text(
                              c['name'],
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              '${c['online'] == true ? '在线' : '离线 · 已保留配对'}${c['id'] == previewComputers.selected ? ' · 当前电脑' : ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: c['id'] == previewComputers.selected
                                ? const Icon(Icons.check, size: 20)
                                : const Icon(Icons.chevron_right),
                            onTap: () async {
                              await previewComputers.choose(c['id']);
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final added = await showPreviewPairing(ctx);
                if (added == true && ctx.mounted) Navigator.pop(ctx);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加电脑'),
            ),
            if (previewComputers.current['online'] != true ||
                previewComputers.connecting)
              TextButton(
                onPressed: previewComputers.connecting
                    ? null
                    : previewComputers.retry,
                child: Text(previewComputers.connecting ? '正在连接…' : '重试连接当前电脑'),
              ),
            const SizedBox(height: 8),
            Text(
              previewComputers.persistenceError ??
                  '演示电脑会保存在当前浏览器，再次打开默认连接上次使用的电脑。',
              style: const TextStyle(
                fontSize: 11,
                height: 1.6,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<bool?> showPreviewPairing(BuildContext context) async {
  final name = TextEditingController(text: '第二台电脑');
  final address = TextEditingController(text: 'http://second.preview.invalid');
  final code = TextEditingController();
  String? error;
  bool offline = false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, change) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              24 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '添加电脑',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '取消添加电脑',
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Text(
                  '原有电脑与配对信息会保留。',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '电脑名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(labelText: '电脑地址（演示）'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '配对码',
                    helperText: '演示配对码：123456',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '配对后模拟电脑离线',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: offline,
                  onChanged: (v) => change(() => offline = v),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final uri = Uri.tryParse(address.text.trim());
                    if (name.text.trim().isEmpty ||
                        uri == null ||
                        !['http', 'https'].contains(uri.scheme) ||
                        uri.host.isEmpty ||
                        uri.userInfo.isNotEmpty ||
                        code.text.trim() != '123456') {
                      change(() => error = '请填写电脑名称、有效地址及演示配对码 123456');
                      return;
                    }
                    final existing = previewComputers.computers
                        .where((c) => c['address'] == address.text.trim())
                        .firstOrNull;
                    if (existing != null) {
                      change(() => error = '这台电脑已配对，请从电脑列表切换');
                      return;
                    }
                    final id = 'demo-${DateTime.now().microsecondsSinceEpoch}';
                    previewComputers.computers.add({
                      'id': id,
                      'name': name.text.trim(),
                      'address': address.text.trim(),
                      'online': !offline,
                    });
                    await previewComputers.choose(id);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  child: const Text('模拟配对并连接'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '仅保存演示名称和地址，不保存配对码，不连接真实电脑。',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  // Controllers may still be referenced by the sheet's exit animation.
  Future<void>.delayed(const Duration(seconds: 1), () {
    name.dispose();
    address.dispose();
    code.dispose();
  });
  return result;
}
