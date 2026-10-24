import 'package:flutter/material.dart';

import 'main.dart' as product;
import 'api.dart';
import 'preview_computers.dart';
import 'preview_pairing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await previewComputers.restore();
  final params = Uri.base.queryParameters;
  final theme = product.CollieApp();
  product.appTheme.value = params['theme'] == 'dark'
      ? ThemeMode.dark
      : ThemeMode.light;
  runApp(
    ValueListenableBuilder<ThemeMode>(
      valueListenable: product.appTheme,
      builder: (_, mode, __) => MaterialApp(
        title: 'G-Collie · 同源 Flutter 原型',
        debugShowCheckedModeBanner: false,
        theme: theme.theme(Brightness.light),
        darkTheme: theme.theme(Brightness.dark),
        themeMode: mode,
        home: PreviewEntry(firstPairing: params['page'] == 'pair'),
      ),
    ),
  );
}

class PreviewComputerWorkspace extends StatefulWidget {
  const PreviewComputerWorkspace({super.key});
  @override
  State<PreviewComputerWorkspace> createState() =>
      _PreviewComputerWorkspaceState();
}

class _PreviewComputerWorkspaceState extends State<PreviewComputerWorkspace> {
  final Map<String, CollieApi> apis = {};
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: previewComputers,
    builder: (ctx, _) {
      final computer = previewComputers.current;
      final id = computer['id'] as String;
      final api = apis.putIfAbsent(
        id,
        () => CollieApi(
          Uri.parse('http://preview.invalid'),
          previewName: computer['name'],
          previewComputerId: id,
        ),
      );
      api.previewOffline =
          computer['online'] != true || previewComputers.connecting;
      for (final session in api.sessions.values) {
        session['readOnly'] = api.previewOffline;
        session['desktopControl'] = !api.previewOffline;
      }
      final params = Uri.base.queryParameters;
      return product.Workspace(
        key: ValueKey(id),
        api: api,
        role: params['state'] == 'readonly' ? 'view' : 'control',
        initialSession: (params['page'] == 'chat' || params['state'] == 'quota')
            ? 'codex:demo'
            : null,
      );
    },
  );
}

class PreviewEntry extends StatefulWidget {
  final bool firstPairing;
  const PreviewEntry({super.key, required this.firstPairing});
  @override
  State<PreviewEntry> createState() => _PreviewEntryState();
}

class _PreviewEntryState extends State<PreviewEntry> {
  late bool pairing = widget.firstPairing;
  @override
  Widget build(BuildContext context) => pairing
      ? PreviewPairingPage(onPaired: () => setState(() => pairing = false))
      : const PreviewComputerWorkspace();
}
