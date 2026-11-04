import 'dart:convert';
// Browser-only fixture navigation; the Flutter engine stays loaded.
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/material.dart';

import 'main.dart' as product;
import 'api.dart';
import 'preview_computers.dart';
import 'preview_pairing.dart';

ThemeData previewTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = product.CollieApp().theme(brightness);
  final ink = dark ? const Color(0xffeeeeee) : const Color(0xff171717);
  final surface = dark ? const Color(0xff212121) : Colors.white;
  final scheme = base.colorScheme.copyWith(
    primary: ink,
    onPrimary: surface,
    surface: surface,
    secondary: ink,
    onSecondary: surface,
    surfaceTint: Colors.transparent,
    primaryContainer: dark ? const Color(0xff363636) : const Color(0xffeeeeee),
    onPrimaryContainer: ink,
    secondaryContainer: dark
        ? const Color(0xff363636)
        : const Color(0xffeeeeee),
    onSecondaryContainer: ink,
  );
  return base.copyWith(
    colorScheme: scheme,
    textTheme: base.textTheme.apply(fontFamilyFallback: const ['PrototypeCJK']),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamilyFallback: const ['PrototypeCJK'],
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: ink.withValues(alpha: .25)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ink),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? surface : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? ink : null,
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  html.window.onMessage.listen((event) {
    if (event.origin != html.window.location.origin || event.data is! String) return;
    dynamic message;
    try {
      message = jsonDecode(event.data as String);
    } on FormatException {
      return; // Readiness and other plain-text messages are not navigation.
    }
    if (message is! Map || message['type'] != 'prototype:navigate') return;
    final query = message['query'];
    if (query is! String) return;
    html.window.history.replaceState(null, '', '?$query');
    startPreview();
  });
  await startPreview();
  html.window.parent?.postMessage('prototype:ready', html.window.location.origin);
}

Future<void> startPreview() async {
  previewComputers.current['online'] = true;
  await previewComputers.restore();
  // Restarting a fixture must not restore another scenario's draft/history.
  // These keys exist only on the prototype origin and synthetic computer.
  try {
    await product.storage.delete(key: 'workspace-drafts:http://preview.invalid');
    await product.storage.delete(key: 'workspace-cache:http://preview.invalid');
  } catch (_) {}
  final params = Uri.base.queryParameters;
  product.appTheme.value = params['theme'] == 'dark'
      ? ThemeMode.dark
      : ThemeMode.light;
  runApp(
    ValueListenableBuilder<ThemeMode>(
      key: UniqueKey(),
      valueListenable: product.appTheme,
      builder: (_, mode, __) => MaterialApp(
        title: 'G-Collie · 同源 Flutter 原型',
        debugShowCheckedModeBanner: false,
        theme: previewTheme(Brightness.light),
        darkTheme: previewTheme(Brightness.dark),
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
      final initialSession = [
              'hermes',
              'video',
              'approval',
              'question',
              'secret',
            ].contains(params['page'])
            ? 'hermes:demo'
            : params['page'] == 'claude'
            ? 'claude:demo'
            : (['chat', 'attachments'].contains(params['page']) ||
                  params['state'] == 'quota')
            ? 'codex:demo'
            : null;
      return product.Workspace(
        key: ValueKey(id),
        api: api,
        role: 'control',
        initialSession: initialSession,
        initialData: {
          'sessions': params['state'] == 'empty' ? [] : api.sessions.values.toList(),
          'projects': api.projects,
          'detail': api.sessions[initialSession],
          'online': !api.previewOffline,
        },
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
