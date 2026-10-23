import 'package:flutter/material.dart';
import 'api.dart';

class NewProjectSheet extends StatefulWidget {
  final CollieApi api;
  const NewProjectSheet({super.key, required this.api});
  @override
  State<NewProjectSheet> createState() => _NewProjectState();
}

class _NewProjectState extends State<NewProjectSheet> {
  final name = TextEditingController();
  String? path;
  String error = '';
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> pick(bool create) async {
    final chosen = await Navigator.of(context).push<Json>(
      MaterialPageRoute(
        builder: (_) =>
            ComputerFolders(api: widget.api, create: create, initial: path),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      path = chosen['path'];
      name.text = chosen['name'] ?? path!.split('/').last;
      error = '';
    });
  }

  Future<void> add() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await widget.api.call('/projects', {
        'path': path,
        'name': name.text,
      });
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(result));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '新建项目',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: busy ? null : () => pick(false),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('选择已有文件夹'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => pick(true),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('新建文件夹'),
            ),
            const SizedBox(height: 16),
            if (path != null) ...[
              Text(path!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                enabled: !busy,
                maxLength: 100,
                decoration: const InputDecoration(labelText: '项目名称'),
              ),
            ] else
              const Text('选择电脑上的文件夹作为项目目录。'),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: path == null || busy ? null : add,
              child: Text(busy ? '正在添加…' : '添加项目'),
            ),
          ],
        ),
      ),
    ),
  );
}

class ComputerFolders extends StatefulWidget {
  final CollieApi api;
  final bool create;
  final String? initial;
  const ComputerFolders({
    super.key,
    required this.api,
    required this.create,
    this.initial,
  });
  @override
  State<ComputerFolders> createState() => _FoldersState();
}

class _FoldersState extends State<ComputerFolders> {
  Json? listing;
  String error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load(widget.initial);
  }

  Future<void> load(String? path) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await widget.api.call(
        '/folders${path == null ? '' : '?path=${Uri.encodeQueryComponent(path)}'}',
      );
      if (mounted) setState(() => listing = Map<String, dynamic>.from(result));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choose() async {
    final path = listing!['path'] as String;
    if (!widget.create) {
      Navigator.pop(context, {'path': path, 'name': path.split('/').last});
      return;
    }
    final field = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (field.text.trim().isNotEmpty) {
                Navigator.pop(ctx, field.text.trim());
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    field.dispose();
    if (name == null || !mounted) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final folder = await widget.api.call('/folders', {
        'parent': path,
        'name': name,
      });
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(folder));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.create ? '选择新文件夹的位置' : '选择电脑文件夹')),
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (listing != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                listing!['path'],
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (busy) const LinearProgressIndicator(),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                if (listing?['parent'] != null)
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: const Text('上一级'),
                    onTap: busy ? null : () => load(listing!['parent']),
                  ),
                for (final f in listing?['folders'] ?? [])
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(f['name']),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: busy ? null : () => load(f['path']),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: busy || listing == null ? null : choose,
              child: Text(widget.create ? '在此新建文件夹' : '选择此文件夹'),
            ),
          ),
        ],
      ),
    ),
  );
}
