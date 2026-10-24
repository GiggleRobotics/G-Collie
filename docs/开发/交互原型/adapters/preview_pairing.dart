import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'preview_computers.dart';

// Prototype-only onboarding. Never contacts the entered address.
class PreviewPairingPage extends StatefulWidget {
  final VoidCallback onPaired;
  const PreviewPairingPage({super.key, required this.onPaired});
  @override
  State<PreviewPairingPage> createState() => _PreviewPairingPageState();
}

class _PreviewPairingPageState extends State<PreviewPairingPage> {
  final address = TextEditingController();
  final phone = TextEditingController();
  final code = TextEditingController();
  bool busy = false;
  String? error;
  bool get ready =>
      address.text.trim().isNotEmpty && RegExp(r'^\d{6}$').hasMatch(code.text);
  @override
  void dispose() {
    address.dispose();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> pair() async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final uri = serverUri(address.text);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      if (code.text != '123456') throw ApiException('配对码错误或已过期，请在电脑端重新获取。');
      final base = '${uri.scheme}://${uri.authority}';
      final existing = previewComputers.computers
          .where((c) => c['address'] == base)
          .firstOrNull;
      final id =
          existing?['id'] ?? 'demo-${DateTime.now().microsecondsSinceEpoch}';
      if (existing == null) {
        previewComputers.computers.add({
          'id': id,
          'name': '新配对的电脑',
          'address': base,
          'online': true,
          'phoneName': phone.text.trim().isEmpty ? '我的手机' : phone.text.trim(),
        });
      } else {
        existing['online'] = true;
        existing['phoneName'] = phone.text.trim().isEmpty
            ? '我的手机'
            : phone.text.trim();
      }
      await previewComputers.choose(id);
      if (mounted) widget.onPaired();
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 40,
      title: const Text('G-Collie', style: TextStyle(fontSize: 14)),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '连接你的第一台电脑',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  '在要连接的电脑上打开 G-Collie，进入“手机与配对”，获取电脑地址和 6 位配对码。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: address,
                  enabled: !busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) => setState(() => error = null),
                  decoration: const InputDecoration(
                    labelText: '电脑地址',
                    hintText: '例如：http://100.x.x.x:4310',
                    helperText: '填写电脑端显示的完整地址，包含 http:// 或 https://',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: code,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  autocorrect: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: (_) => setState(() => error = null),
                  decoration: const InputDecoration(
                    labelText: '6 位配对码',
                    hintText: '输入电脑端显示的配对码',
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: phone,
                  enabled: !busy,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: '本手机名称（选填）',
                    hintText: '例如：我的手机',
                    helperText: '用于在电脑端识别这部手机',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 20),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: !busy && ready ? pair : null,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: Text(busy ? '正在配对…' : '配对并连接'),
                ),
                const SizedBox(height: 16),
                Text(
                  '配对成功后进入会话首页。以后打开 App 会自动连接上次使用的电脑。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '原型演示\n电脑地址可填 http://preview.invalid，配对码为 123456。仅保存演示信息，不连接真实电脑。',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.7,
                      color: Colors.grey,
                    ),
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
