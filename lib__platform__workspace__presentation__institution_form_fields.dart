import 'package:flutter/material.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';

/// The institution types offered in the wizard and the profile screen.
/// The stored value is the English label (English-only in version 1).
List<String> institutionTypes(AppLocalizations l10n) => [
      l10n.typeSchool,
      l10n.typeJuniorCollege,
      l10n.typeSeniorCollege,
      l10n.typeCoaching,
      l10n.typeOther,
    ];

String? requiredText(AppLocalizations l10n, String? value) =>
    (value == null || value.trim().isEmpty) ? l10n.fieldRequired : null;

String? optionalEmail(AppLocalizations l10n, String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim()) ? null : l10n.invalidEmail;
}

/// A labelled text field for forms, spaced consistently.
class FormFieldRow extends StatelessWidget {
  const FormFieldRow({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textCapitalization: keyboardType == null ? TextCapitalization.words : TextCapitalization.none,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}

/// Choice chips for the institution type.
class InstitutionTypeChoice extends StatelessWidget {
  const InstitutionTypeChoice({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.fieldType, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: SdSpace.sm),
          Wrap(
            spacing: SdSpace.sm,
            runSpacing: SdSpace.sm,
            children: [
              for (final type in institutionTypes(l10n))
                ChoiceChip(label: Text(type), selected: type == value, onSelected: (_) => onChanged(type)),
            ],
          ),
        ],
      ),
    );
  }
}
