import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';

/// A row of colour swatches; the selected one carries a check mark.
class SdColorChoice extends StatelessWidget {
  const SdColorChoice({super.key, required this.selected, required this.onChanged, this.choices = SdPalette.brandChoices});

  final Color selected;
  final ValueChanged<Color> onChanged;
  final List<Color> choices;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SdSpace.md,
      runSpacing: SdSpace.md,
      children: [
        for (final color in choices)
          Semantics(
            button: true,
            selected: color.toARGB32() == selected.toARGB32(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onChanged(color),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.toARGB32() == selected.toARGB32()
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: color.toARGB32() == selected.toARGB32()
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
