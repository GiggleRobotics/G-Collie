import 'package:flutter/material.dart';
import 'main.dart' as product;
import 'api.dart';

void main() {
  final params = Uri.base.queryParameters;
  final theme = product.CollieApp();
  product.appTheme.value = params['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light;
  runApp(ValueListenableBuilder<ThemeMode>(valueListenable: product.appTheme, builder: (_, mode, __) => MaterialApp(
    title: 'G-Collie · 同源 Flutter 原型',
    debugShowCheckedModeBanner: false,
    theme: theme.theme(Brightness.light),
    darkTheme: theme.theme(Brightness.dark),
    themeMode: mode,
    home: params['page'] == 'pair'
        ? const product.ConnectionPage()
        : product.Workspace(
            api: CollieApi(Uri.parse('http://preview.invalid')),
            role: params['state'] == 'readonly' ? 'view' : 'control',
            initialSession: params['page'] == 'chat' ? 'codex:demo' : null,
          ),
  )));
}
