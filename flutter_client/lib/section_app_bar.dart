import 'package:flutter/material.dart';

/// Matches workspace section headers: 12px inset + 48px back target + 5px gap.
class SectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool primary;
  const SectionAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.primary = true,
  });
  @override
  Size get preferredSize => const Size.fromHeight(52);
  @override
  Widget build(BuildContext context) => AppBar(
    primary: primary,
    toolbarHeight: 52,
    leadingWidth: 60,
    titleSpacing: 5,
    centerTitle: false,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).colorScheme.onSurface,
    ),
    leading: Padding(
      padding: const EdgeInsets.only(left: 12),
      child:
          leading ??
          IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 23),
          ),
    ),
    title: title,
    actions: actions,
  );
}
