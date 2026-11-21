import 'package:flutter/material.dart';

import 'native.dart';

/// Original centered about sheet, with a short product description.
class AboutContent extends StatefulWidget {
  const AboutContent({super.key});
  @override
  State<AboutContent> createState() => _AboutContentState();
}

class _AboutContentState extends State<AboutContent> {
  late final version = NativeBridge.appVersion();
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: .55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Image.asset(
              'assets/collie-mark-v2.png',
              width: 59,
              height: 59,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            label: 'G-Collie · Agent 会话控制台',
            excludeSemantics: true,
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              child: const Wrap(
                alignment: WrapAlignment.center,
                spacing: 5,
                children: [
                  Text('G-Collie ·'),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 5,
                    children: [Text('Agent'), Text('会话控制台')],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          FutureBuilder<String>(
            future: version,
            builder: (context, snapshot) => Text(
              snapshot.hasData ? '${snapshot.data} · By Giggle' : '正在读取版本…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '帮你照看每一个 Agent',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 16),
          const Text(
            '本版更新：Codex / Hermes / Claude Code 会话、项目用量、照片与文件、工作台设置。',
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 14, height: 1.7),
          ),
          const SizedBox(height: 12),
          const Text(
            '反馈时请提供页面提示、Agent 类型及会话 ID，方便定位问题。',
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 14, height: 1.7),
          ),
        ],
      ),
    );
  }
}
