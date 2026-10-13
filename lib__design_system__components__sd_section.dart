import 'package:flutter/material.dart';

import '../tokens/spacing.dart';

/// A titled block of content on a screen.
class SdSection extends StatelessWidget {
  const SdSection({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: SdSpace.md),
        child,
      ],
    );
  }
}

/// Centres page content and caps its width so lines stay readable on desktop.
class SdPage extends StatelessWidget {
  const SdPage({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < SdBreakpoints.compact ? SdSpace.lg : SdSpace.xl;
    return ListView(
      padding: EdgeInsets.symmetric(vertical: pad),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: SdBreakpoints.maxContentWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ),
      ],
    );
  }
}
