import 'package:flutter/material.dart';

class StatusNotice extends StatelessWidget {
  final String title, message, connection, primaryLabel;
  final IconData icon;
  final VoidCallback? onPrimary, onSecondary;
  final String? badge;
  final bool checking;
  const StatusNotice({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.connection,
    required this.primaryLabel,
    this.onPrimary,
    this.onSecondary,
    this.badge,
    this.checking = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: c.onSurface),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 6),
                  child: Text(
                    badge!,
                    style: TextStyle(fontSize: 10, color: c.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              height: 1.7,
              color: c.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.computer_outlined,
                size: 13,
                color: c.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                connection,
                style: TextStyle(fontSize: 11, color: c.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton(
                    onPressed: checking ? null : onPrimary,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: checking
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: c.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('正在检查'),
                            ],
                          )
                        : Text(primaryLabel),
                  ),
                ),
              ),
              if (onSecondary != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextButton(
                      onPressed: onSecondary,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('查看用量'),
                          SizedBox(width: 3),
                          Icon(Icons.chevron_right, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
