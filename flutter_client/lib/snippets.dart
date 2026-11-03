import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SnippetLibrary extends StatefulWidget {
  const SnippetLibrary({super.key});
  @override
  State<SnippetLibrary> createState() => _SnippetLibraryState();
}

class _SnippetLibraryState extends State<SnippetLibrary> {
  static const storage = FlutterSecureStorage();
  final field = TextEditingController();
  List<String> rows = [];
  String error = '';
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final raw = await storage.read(key: 'prompt-snippets-v1');
      if (mounted) {
        setState(
          () => rows = raw == null ? [] : List<String>.from(jsonDecode(raw)),
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = '无法读取片段库，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save(List<String> next) async {
    setState(() => busy = true);
    try {
      await storage.write(key: 'prompt-snippets-v1', value: jsonEncode(next));
      if (mounted) {
        setState(() {
          rows = next;
          error = '';
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '片段未保存，请检查设备存储后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('提示词片段')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('片段仅保存在本设备。插入草稿后可继续编辑，不会自动发送。'),
        const SizedBox(height: 16),
        TextField(
          controller: field,
          minLines: 3,
          maxLines: 6,
          maxLength: 4000,
          decoration: const InputDecoration(hintText: '输入常用提示词'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    busy || field.text.trim().isEmpty || rows.length >= 100
                    ? null
                    : () async {
                        final value = field.text.trim();
                        await save([value, ...rows.where((s) => s != value)]);
                      },
                child: const Text('保存到片段库'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: busy || field.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, field.text.trim()),
                child: const Text('插入草稿'),
              ),
            ),
          ],
        ),
        if (error.isNotEmpty) Text(error),
        const SizedBox(height: 24),
        Text('已保存 ${rows.length} / 100'),
        for (final row in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row, maxLines: 3, overflow: TextOverflow.ellipsis),
            onTap: busy ? null : () => Navigator.pop(context, row),
            trailing: IconButton(
              tooltip: '删除片段',
              icon: const Icon(Icons.delete_outline),
              onPressed: busy
                  ? null
                  : () async {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('删除此片段？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (yes == true) {
                        await save(rows.where((s) => s != row).toList());
                      }
                    },
            ),
          ),
      ],
    ),
  );
}
