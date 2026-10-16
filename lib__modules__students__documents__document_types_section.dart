import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import 'document_models.dart';
import 'document_providers.dart';

/// Settings: the documents students submit, which are required (for which
/// classes, only for reserved categories) and which hold Aadhaar.
class DocumentTypesSection extends ConsumerWidget {
  const DocumentTypesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final types = ref.watch(documentTypesProvider).valueOrNull ?? DocumentTypes.defaults;
    final programs = ref.watch(academicControllerProvider).programs;

    Future<void> save(List<DocumentType> next) async {
      try {
        await ref.read(documentRepositoryProvider).saveTypes(next);
        ref.read(documentsRevisionProvider.notifier).state++;
      } catch (_) {
        if (context.mounted) SdToast.show(context, l10n.saveFailed);
      }
    }

    Future<void> add() async {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(l10n.docTypeAdd),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.docTypeName),
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            SdButton(label: l10n.cancel, variant: SdButtonVariant.text, onPressed: () => Navigator.of(dialog).pop()),
            SdButton(label: l10n.save, onPressed: () => Navigator.of(dialog).pop(controller.text.trim())),
          ],
        ),
      );
      controller.dispose();
      if (name == null || name.isEmpty) return;
      final key = DocumentTypes.keyFor(name, types.map((t) => t.key));
      await save([...types, DocumentType(key: key, label: name)]);
    }

    Future<void> editClasses(int i) async {
      final chosen = {...types[i].programIds};
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text(l10n.docTypeClasses(types[i].label)),
            content: Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
              for (final p in programs)
                FilterChip(
                  label: Text(p.name),
                  selected: chosen.contains(p.id),
                  onSelected: (on) => setLocal(() => on ? chosen.add(p.id) : chosen.remove(p.id)),
                ),
            ]),
            actions: [
              SdButton(label: l10n.cancel, variant: SdButtonVariant.text, onPressed: () => Navigator.of(dialog).pop(false)),
              SdButton(label: l10n.save, onPressed: () => Navigator.of(dialog).pop(true)),
            ],
          ),
        ),
      );
      if (ok != true) return;
      final next = [...types];
      next[i] = next[i].copyWith(programIds: chosen.toList());
      await save(next);
    }

    return SdSection(
      title: l10n.docTypesTitle,
      trailing: SdButton(label: l10n.docTypeAdd, icon: Icons.add, variant: SdButtonVariant.text, onPressed: add),
      child: SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.docTypesHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: SdSpace.sm),
            for (var i = 0; i < types.length; i++) ...[
              if (i > 0) const Divider(height: SdSpace.lg),
              Row(children: [
                Expanded(child: Text(types[i].label, style: theme.textTheme.titleSmall)),
                IconButton(
                  tooltip: l10n.docTypeRemove,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await SdDialog.confirm(
                      context,
                      title: l10n.docTypeRemove,
                      message: l10n.docTypeRemoveConfirm(types[i].label),
                      confirmLabel: l10n.docTypeRemove,
                      cancelLabel: l10n.cancel,
                    );
                    if (ok) await save([...types]..removeAt(i));
                  },
                ),
              ]),
              Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.xs, children: [
                FilterChip(
                  label: Text(l10n.docRequired),
                  selected: types[i].isRequired,
                  onSelected: (v) => save([...types]..[i] = types[i].copyWith(isRequired: v)),
                ),
                if (types[i].isRequired) ...[
                  FilterChip(
                    label: Text(l10n.docOnlyReserved),
                    selected: types[i].onlyReserved,
                    onSelected: (v) => save([...types]..[i] = types[i].copyWith(onlyReserved: v)),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.groups_outlined, size: 18),
                    label: Text(types[i].programIds.isEmpty
                        ? l10n.docAllClasses
                        : l10n.docSomeClasses(types[i].programIds.length)),
                    onPressed: () => editClasses(i),
                  ),
                ],
                FilterChip(
                  label: Text(l10n.docSensitive),
                  selected: types[i].sensitive,
                  onSelected: (v) => save([...types]..[i] = types[i].copyWith(sensitive: v)),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
