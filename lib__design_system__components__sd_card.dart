import 'package:flutter/material.dart';

import '../tokens/spacing.dart';

/// Bordered surface for grouping content. Tappable when [onTap] is set.
class SdCard extends StatelessWidget {
  const SdCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SdSpace.lg),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
