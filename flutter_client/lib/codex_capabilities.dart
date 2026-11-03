import 'package:flutter/material.dart';
import 'api.dart';

class CodexCapabilities extends StatefulWidget {
  final CollieApi api;
  final String session;
  final bool enabled;
  const CodexCapabilities({
    super.key,
    required this.api,
    required this.session,
    required this.enabled,
  });
  @override
  State<CodexCapabilities> createState() => _CodexCapabilitiesState();
}

class _CodexCapabilitiesState extends State<CodexCapabilities> {
  Json? data;
  String error = '';
  bool busy = false;
  final objective = TextEditingController();
  String get root => '/local/${Uri.encodeComponent(widget.session)}';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    objective.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final d = await widget.api.call('$root/codex-capabilities');
      if (mounted) {
        setState(() {
          data = Map<String, dynamic>.from(d);
          objective.text = '${d['goal']?['data']?['goal']?['objective'] ?? ''}';
          error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(String suffix, Json value) async {
    if (!widget.enabled || busy) return;
    setState(() => busy = true);
    try {
      await widget.api.call('$root/$suffix', value);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modes = data?['modes']?['data']?['data'] as List? ?? [];
    final markets = data?['plugins']?['data']?['marketplaces'] as List? ?? [];
    final plugins = [for (final m in markets) ...(m['plugins'] as List? ?? [])];
    return Scaffold(
      appBar: AppBar(title: const Text('Codex 能力')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (error.isNotEmpty) Text(error),
          if (busy) const LinearProgressIndicator(),
          const Text(
            '计划模式',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (data?['modes']?['error'] != null)
            Text('${data!['modes']['error']}'),
          for (final m in modes)
            ListTile(
              title: Text(m['mode'] == 'plan' ? '计划模式' : '默认模式'),
              leading: Icon(
                (data?['mode'] ?? 'default') == m['mode']
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              onTap: !widget.enabled || busy
                  ? null
                  : () => action('mode', {'mode': m['mode']}),
            ),
          const Text('计划模式在下一轮发送时生效，不改变当前执行中的任务。'),
          const SizedBox(height: 24),
          const Text(
            '持续目标',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const Text('设置当前 Codex 会话的原生目标。实际推进受当前账号与任务状态约束。'),
          if (data?['goal']?['error'] != null)
            Text('${data!['goal']['error']}'),
          TextField(
            controller: objective,
            maxLength: 4000,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(hintText: '输入目标'),
            onChanged: (_) => setState(() {}),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: !widget.enabled || busy
                      ? null
                      : () => action('goal', {'action': 'clear'}),
                  child: const Text('清除目标'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed:
                      !widget.enabled || busy || objective.text.trim().isEmpty
                      ? null
                      : () => action('goal', {
                          'action': 'set',
                          'objective': objective.text.trim(),
                        }),
                  child: const Text('保存目标'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            '已安装插件',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const Text('读取电脑原生插件目录，不自动安装或授权。'),
          if (data?['plugins']?['error'] != null)
            Text('${data!['plugins']['error']}'),
          for (final p in plugins)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${p['interface']?['displayName'] ?? p['name']}'),
              subtitle: Text(
                '${p['interface']?['shortDescription'] ?? p['name']}',
              ),
              trailing: Text(p['enabled'] == true ? '已启用' : '未启用'),
            ),
          for (final skill in data?['skills'] as List? ?? [])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${skill['plugin']} · ${skill['name']}'),
              trailing: const Icon(Icons.add),
              enabled: widget.enabled && !busy,
              onTap: () => Navigator.pop(context, {
                'skillId': skill['id'],
                'name': '${skill['plugin']} · ${skill['name']}',
              }),
            ),
          TextButton(onPressed: busy ? null : load, child: const Text('重新检查')),
        ],
      ),
    );
  }
}
