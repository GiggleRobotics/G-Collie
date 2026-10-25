import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';

class ConnectionPage extends StatefulWidget {
  final CollieApi? api;
  final PreferredSizeWidget appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  const ConnectionPage({
    super.key,
    this.api,
    required this.appBar,
    required this.body,
    this.bottomNavigationBar,
  });
  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  Timer? timer;
  String name = '电脑', status = '连接中';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    try {
      final api = widget.api;
      if (api == null) throw Exception();
      final r = await api.call('/network');
      if (mounted)
        setState(() {
          name = r['computerName'] ?? api.base.host;
          status = '已连接';
        });
    } catch (_) {
      if (mounted) setState(() => status = '未连接');
    } finally {
      busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PreferredSize(
      preferredSize: Size.fromHeight(40 + widget.appBar.preferredSize.height),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.computer_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: status == '已连接'
                            ? const Color(0xff00d600)
                            : status == '连接中'
                            ? const Color(0xffb88a00)
                            : const Color(0xffef4444),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(status, style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 32,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        onSelected: (_) => refresh(),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'retry',
                            child: Text('重新连接'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            widget.appBar,
          ],
        ),
      ),
    ),
    body: widget.body,
    bottomNavigationBar: widget.bottomNavigationBar,
  );
}
