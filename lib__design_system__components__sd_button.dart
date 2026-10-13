import 'package:flutter/material.dart';

import '../tokens/colors.dart';

enum SdButtonVariant { primary, secondary, text, danger }

/// The only button screens should use. Variants keep emphasis consistent:
/// one primary action per screen, secondary for the rest.
class SdButton extends StatelessWidget {
  const SdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = SdButtonVariant.primary,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SdButtonVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final iconWidget = icon == null ? null : Icon(icon, size: 18);
    final text = Text(label);
    final Widget button;
    switch (variant) {
      case SdButtonVariant.primary:
        button = iconWidget == null
            ? FilledButton(onPressed: onPressed, child: text)
            : FilledButton.icon(onPressed: onPressed, icon: iconWidget, label: text);
      case SdButtonVariant.secondary:
        button = iconWidget == null
            ? OutlinedButton(onPressed: onPressed, child: text)
            : OutlinedButton.icon(onPressed: onPressed, icon: iconWidget, label: text);
      case SdButtonVariant.text:
        button = iconWidget == null
            ? TextButton(onPressed: onPressed, child: text)
            : TextButton.icon(onPressed: onPressed, icon: iconWidget, label: text);
      case SdButtonVariant.danger:
        final style = FilledButton.styleFrom(backgroundColor: SdColors.of(context).absent);
        button = iconWidget == null
            ? FilledButton(onPressed: onPressed, style: style, child: text)
            : FilledButton.icon(onPressed: onPressed, style: style, icon: iconWidget, label: text);
    }
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
