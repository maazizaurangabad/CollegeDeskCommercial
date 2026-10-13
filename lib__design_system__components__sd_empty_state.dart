import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';

/// Shown when a list has nothing in it. Always says what to do next.
class SdEmptyState extends StatelessWidget {
  const SdEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(SdSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: sd.subtleFill, borderRadius: BorderRadius.circular(SdRadius.md)),
                child: Icon(icon, size: 28, color: sd.textMuted),
              ),
              const SizedBox(height: SdSpace.lg),
              Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: SdSpace.sm),
              Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: sd.textMuted), textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: SdSpace.xl), action!],
            ],
          ),
        ),
      ),
    );
  }
}
