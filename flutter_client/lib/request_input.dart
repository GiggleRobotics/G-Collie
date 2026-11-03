import 'package:flutter/material.dart';
import 'api.dart';

/// Request-scoped input: values stay out of the conversation composer.
class RequestInputCard extends StatefulWidget {
  final Json request;
  final bool enabled;
  final Future<bool> Function(Json answer) onSubmit;
  const RequestInputCard({
    super.key,
    required this.request,
    required this.enabled,
    required this.onSubmit,
  });
  @override
  State<RequestInputCard> createState() => _RequestInputCardState();
}

class _RequestInputCardState extends State<RequestInputCard> {
  final secret = TextEditingController();
  final controllers = <String, TextEditingController>{};
  final answers = <String, String>{};
  final custom = <String>{};
  bool visible = false, submitting = false;
  bool get isSecret => widget.request['kind'] == 'secret';
  bool get isApproval => widget.request['kind'] == 'approval';
  String? decision;
  bool allows(String choice) =>
      params['availableDecisions'] == null ||
      (params['availableDecisions'] as List).contains(choice);
  Map get params => widget.request['params'] as Map? ?? {};
  List get questions => params['questions'] as List? ?? [];
  String questionId(Map q, int index) => '${q['id'] ?? index}';
  bool get enabled => widget.enabled && !submitting;
  bool get ready => isSecret
      ? secret.text.isNotEmpty
      : questions.isNotEmpty &&
            questions.asMap().entries.every(
              (e) => (answers[questionId(e.value as Map, e.key)] ?? '')
                  .trim()
                  .isNotEmpty,
            );

  Future<void> submit({bool cancel = false}) async {
    if (!enabled || (!cancel && !ready)) return;
    final Json answer = isSecret
        ? {'value': cancel ? '' : secret.text}
        : {'answers': Map<String, String>.from(answers)};
    setState(() {
      submitting = true;
      visible = false;
      if (isSecret) secret.clear();
    });
    try {
      await widget.onSubmit(answer);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> decide(String choice) async {
    if (!enabled || !allows(choice)) return;
    setState(() {
      submitting = true;
      decision = choice;
    });
    try {
      await widget.onSubmit({'decision': choice});
    } finally {
      if (mounted) {
        setState(() {
          submitting = false;
          decision = null;
        });
      }
    }
  }

  Widget approvalBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${params['reason'] ?? '助手需要你确认后才能继续此操作。'}',
        style: const TextStyle(fontSize: 14, height: 1.6),
      ),
      if (params['command'] != null) ...[
        const SizedBox(height: 14),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: PageStorageKey('approval-command:${widget.request['id']}'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              title: const Text('查看将执行的命令', style: TextStyle(fontSize: 13)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    '${params['command']}',
                    key: PageStorageKey(
                      'approval-command-content:${widget.request['id']}',
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Text(
        '仅批准本次请求，不更改后续权限。拒绝后由助手处理结果。',
        style: TextStyle(
          fontSize: 12,
          height: 1.6,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget approvalActions() => Row(
    children: [
      if (allows('decline'))
        Expanded(
          child: SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: enabled ? () => decide('decline') : null,
              child: Text(submitting && decision == 'decline' ? '正在提交…' : '拒绝'),
            ),
          ),
        ),
      if (allows('decline') && allows('accept')) const SizedBox(width: 12),
      if (allows('accept'))
        Expanded(
          child: SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: enabled ? () => decide('accept') : null,
              child: Text(
                submitting && decision == 'accept' ? '正在提交…' : '批准一次',
              ),
            ),
          ),
        ),
      if (!allows('decline') && !allows('accept'))
        const Expanded(
          child: Text('此请求需在电脑端处理。', style: TextStyle(fontSize: 12)),
        ),
    ],
  );

  @override
  void dispose() {
    secret.dispose();
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    counterText: '',
    filled: true,
    fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget option({
    required String title,
    String? description,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected ? scheme.surfaceContainer : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (description != null && description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget question(Map q, int index) {
    final id = questionId(q, index);
    final options = q['options'] as List? ?? [];
    final controller = controllers.putIfAbsent(
      id,
      () => TextEditingController(),
    );
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (questions.length > 1) ...[
            Text(
              '问题 ${index + 1} / ${questions.length}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            '${q['question'] ?? q['header'] ?? '请填写回答'}',
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
          for (final o in options)
            option(
              title: '${o['label']}',
              description: o['description'] as String?,
              selected: !custom.contains(id) && answers[id] == '${o['label']}',
              onTap: () => setState(() {
                custom.remove(id);
                answers[id] = '${o['label']}';
              }),
            ),
          if (options.isNotEmpty && !custom.contains(id))
            option(
              title: '填写其他回答',
              selected: false,
              onTap: () => setState(() {
                custom.add(id);
                answers[id] = controller.text;
              }),
            ),
          if (options.isEmpty || custom.contains(id)) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('${widget.request['id']}:$id'),
              controller: controller,
              enabled: enabled,
              minLines: 2,
              maxLines: 5,
              maxLength: 4000,
              decoration: inputDecoration('输入你的回答'),
              onChanged: (value) => setState(() => answers[id] = value),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isApproval
                    ? Icons.shield_outlined
                    : isSecret
                    ? Icons.lock_outline
                    : Icons.help_outline,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isApproval
                      ? '需要你的批准'
                      : isSecret
                      ? '需要安全输入'
                      : '需要你的回答',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isApproval)
            approvalBody()
          else if (isSecret) ...[
            Text(
              '${params['prompt'] ?? '请填写本次请求需要的内容'}',
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey('secret:${widget.request['id']}'),
              controller: secret,
              obscureText: !visible,
              enableSuggestions: false,
              autocorrect: false,
              enabled: enabled,
              onChanged: (_) => setState(() {}),
              decoration: inputDecoration('输入所需内容').copyWith(
                suffixIcon: IconButton(
                  tooltip: visible ? '隐藏内容' : '显示内容',
                  onPressed: enabled
                      ? () => setState(() => visible = !visible)
                      : null,
                  icon: Icon(
                    visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 21,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '请确认这次请求的用途后再提交。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            for (final e in questions.asMap().entries)
              question(e.value as Map, e.key),
          ],
          if (!widget.enabled && !submitting) ...[
            const SizedBox(height: 12),
            Text(
              '当前无法操作，请检查连接或在电脑上处理。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 20),
          if (isApproval)
            approvalActions()
          else
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: enabled && ready ? () => submit() : null,
                child: submitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : Text(isSecret ? '提交' : '提交回答'),
              ),
            ),
          if (isSecret) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: TextButton(
                onPressed: enabled ? () => submit(cancel: true) : null,
                child: const Text('取消本次请求'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
