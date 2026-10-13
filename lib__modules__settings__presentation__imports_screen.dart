import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../students/application/students_providers.dart';
import '../../students/import/import_repository.dart';
import 'settings_page_header.dart';

/// Past Excel and photo imports, each with Undo.
class ImportsScreen extends ConsumerWidget {
  const ImportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(studentsRevisionProvider);
    final format = DateFormat('d MMM y, h:mm a');
    return SdPage(
      children: [
        SettingsPageHeader(title: l10n.settingsImports),
        FutureBuilder<List<ImportBatchInfo>>(
          future: ref.read(importRepositoryProvider).listBatches(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SdSkeleton(height: 120);
            final batches = snapshot.data!;
            if (batches.isEmpty) return SdEmptyState(icon: Icons.history, title: l10n.importsEmpty, message: '');
            return SdCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < batches.length; i++) ...[
                    if (i > 0) const Divider(indent: SdSpace.lg),
                    ListTile(
                      leading: Icon(batches[i].kind == 'photos' ? Icons.photo_library_outlined : Icons.table_chart_outlined),
                      title: Text(batches[i].sourceName),
                      subtitle: Text([
                        batches[i].kind == 'photos' ? l10n.importKindPhotos : l10n.importKindStudents,
                        format.format(batches[i].createdAt.toLocal()),
                        l10n.importSummary(batches[i].added, batches[i].updated, batches[i].skipped),
                        if (batches[i].undone) l10n.importUndone,
                      ].join(' · ')),
                      trailing: batches[i].undone
                          ? null
                          : TextButton(
                              onPressed: () async {
                                final ok = await SdDialog.confirm(
                                  context,
                                  title: l10n.importUndo,
                                  message: l10n.importUndoConfirm,
                                  confirmLabel: l10n.importUndo,
                                  cancelLabel: l10n.cancel,
                                  destructive: true,
                                );
                                if (!ok) return;
                                await ref.read(importRepositoryProvider).undo(batches[i].id);
                                ref.read(studentsRevisionProvider.notifier).state++;
                                if (context.mounted) SdToast.show(context, l10n.importUndone);
                              },
                              child: Text(l10n.importUndo),
                            ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
