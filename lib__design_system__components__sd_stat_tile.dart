import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import 'sd_card.dart';

/// A single number with its label, used on the dashboard.
/// [accent] marks the number's meaning (e.g. present green); null keeps it neutral.
class SdStatTile extends StatelessWidget {
  const SdStatTile({super.key, required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              if (accent != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: SdSpace.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(color: SdColors.of(context).textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: SdSpace.sm),
          Text(value, style: theme.textTheme.displaySmall?.copyWith(fontSize: 28)),
        ],
      ),
    );
  }
}
