import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/data/data_providers.dart';
import '../../students/application/students_providers.dart';
import '../../students/domain/student_models.dart';
import 'settings_page_header.dart';

/// Extra student fields and the category list for this institution.
class StudentFieldsScreen extends ConsumerWidget {
  const StudentFieldsScreen({super.key});

  String _typeLabel(AppLocalizations l10n, String type) => switch (type) {
        'number' => l10n.typeNumber,
        'date' => l10n.typeDate,
        'choice' => l10n.typeChoice,
        'yesNo' => l10n.typeYesNo,
        _ => l10n.typeText,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fields = ref.watch(extraFieldsProvider);
    final categories = ref.watch(studentCategoriesProvider).valueOrNull ?? StudentChoices.defaultCategories;
    void changed() => ref.read(studentsRevisionProvider.notifier).state++;

    return SdPage(
      children: [
        SettingsPageHeader(
          title: l10n.settingsStudentFields,
          trailing: SdButton(
            label: l10n.extraFieldAdd,
            icon: Icons.add,
            onPressed: () async {
              final result = await showDialog<_NewField>(context: context, builder: (_) => const _AddFieldDialog());
              if (result == null || !context.mounted) return;
              final ok = await runWithFeedback(
                context,
                () => ref.read(fieldDefinitionRepositoryProvider).add(
                      label: result.label,
                      type: result.type,
                      options: result.options,
                      isRequired: result.required,
                    ),
                (e) => e is StateError ? l10n.fieldExists : l10n.saveFailed,
              );
              if (ok) changed();
            },
          ),
        ),
        SdSection(
          title: l10n.extraFieldsTitle,
          child: fields.when(
            loading: () => const SdSkeleton(height: 120),
            error: (e, _) => Text(l10n.saveFailed),
            data: (list) => list.isEmpty
                ? SdCard(child: Text(l10n.extraFieldsEmpty))
                : SdCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) const Divider(indent: SdSpace.lg),
                          ListTile(
                            title: Text(list[i].label),
                            subtitle: Text([
                              _typeLabel(l10n, list[i].type),
                              if (list[i].isRequired) l10n.extraFieldRequired,
                              if (list[i].options.isNotEmpty) list[i].options.join(', '),
                            ].join(' · ')),
                            trailing: IconButton(
                              tooltip: l10n.delete,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final ok = await SdDialog.confirm(
                                  context,
                                  title: l10n.deleteConfirmTitle(list[i].label),
                                  message: l10n.deleteConfirmMessage,
                                  confirmLabel: l10n.delete,
                                  cancelLabel: l10n.cancel,
                                  destructive: true,
                                );
                                if (!ok || !context.mounted) return;
                                await ref.read(fieldDefinitionRepositoryProvider).remove(list[i].id);
                                changed();
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: SdSpace.xl),
        SdSection(
          title: l10n.categoriesTitle,
          trailing: SdButton(
            label: l10n.categoriesEdit,
            variant: SdButtonVariant.text,
            onPressed: () async {
              final text = await SdDialog.prompt(
                context,
                title: l10n.categoriesEdit,
                label: l10n.categoriesHint,
                confirmLabel: l10n.save,
                cancelLabel: l10n.cancel,
                initial: categories.join(', '),
              );
              if (text == null || !context.mounted) return;
              final ok = await runWithFeedback(
                context,
                () => StudentCategories.save(ref.read(appSettingsRepositoryProvider), text.split(',')),
                (_) => l10n.saveFailed,
              );
              if (ok) changed();
            },
          ),
          child: SdCard(
            child: Wrap(
              spacing: SdSpace.sm,
              runSpacing: SdSpace.sm,
              children: [for (final c in categories) Chip(label: Text(c))],
            ),
          ),
        ),
      ],
    );
  }
}

class _NewField {
  const _NewField(this.label, this.type, this.options, this.required);

  final String label;
  final String type;
  final List<String> options;
  final bool required;
}

class _AddFieldDialog extends StatefulWidget {
  const _AddFieldDialog();

  @override
  State<_AddFieldDialog> createState() => _AddFieldDialogState();
}

class _AddFieldDialogState extends State<_AddFieldDialog> {
  final _label = TextEditingController();
  final _options = TextEditingController();
  String _type = 'text';
  bool _required = false;

  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final types = [
      ('text', l10n.typeText),
      ('number', l10n.typeNumber),
      ('date', l10n.typeDate),
      ('choice', l10n.typeChoice),
      ('yesNo', l10n.typeYesNo),
    ];
    return AlertDialog(
      title: Text(l10n.extraFieldAdd),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.extraFieldLabel),
            ),
            const SizedBox(height: SdSpace.lg),
            SdSelectField<String>(
              label: l10n.extraFieldType,
              value: _type,
              options: types,
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            if (_type == 'choice')
              TextField(controller: _options, decoration: InputDecoration(labelText: l10n.extraFieldOptions)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.extraFieldRequired),
              value: _required,
              onChanged: (v) => setState(() => _required = v),
            ),
          ],
        ),
      ),
      actions: [
        SdButton(label: l10n.cancel, variant: SdButtonVariant.text, onPressed: () => Navigator.of(context).pop()),
        SdButton(
          label: l10n.save,
          onPressed: () {
            if (_label.text.trim().isEmpty) return;
            Navigator.of(context).pop(_NewField(_label.text, _type, _options.text.split(','), _required));
          },
        ),
      ],
    );
  }
}
