import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../tokens/spacing.dart';
import 'sd_feedback.dart';

/// A form field that opens a list to choose from. Works the same on a
/// phone (bottom sheet) and on Windows, and never shows a cramped menu.
class SdSelectField<T> extends StatelessWidget {
  const SdSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.clearLabel,
    this.emptyText = '',
  });

  final String label;
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T?> onChanged;

  /// When set, the list offers an entry that clears the value.
  final String? clearLabel;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    String? text;
    for (final o in options) {
      if (o.$1 == value) text = o.$2;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(SdRadius.sm),
        onTap: () async {
          final picked = await SdSheet.show<(bool, T?)>(
            context,
            title: label,
            builder: (sheet) => ListView(
              shrinkWrap: true,
              children: [
                if (clearLabel != null)
                  ListTile(title: Text(clearLabel!), onTap: () => Navigator.of(sheet).pop((true, null))),
                for (final o in options)
                  ListTile(
                    title: Text(o.$2),
                    trailing: o.$1 == value ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                    onTap: () => Navigator.of(sheet).pop((true, o.$1)),
                  ),
              ],
            ),
          );
          if (picked != null && picked.$1) onChanged(picked.$2);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.expand_more)),
          isEmpty: text == null && emptyText.isEmpty,
          child: Text(text ?? emptyText),
        ),
      ),
    );
  }
}

/// A date shown as text; tap to pick, with an optional clear button.
class SdDateField extends StatelessWidget {
  const SdDateField({super.key, required this.label, required this.value, required this.onChanged, this.clearable = true});

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(SdRadius.sm),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(1950),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: value != null && clearable
                ? IconButton(icon: const Icon(Icons.close), onPressed: () => onChanged(null))
                : const Icon(Icons.event_outlined),
          ),
          isEmpty: value == null,
          child: Text(value == null ? '' : DateFormat('d MMM y').format(value!)),
        ),
      ),
    );
  }
}
