import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/files/save_file.dart';
import '../../../core/files/xlsx_styled.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/organization/organization_providers.dart';
import '../application/students_providers.dart';
import '../domain/student_models.dart';
import '../import/import_labels.dart';
import '../import/import_planner.dart';
import '../import/import_report.dart';
import 'student_labels.dart';

/// After an import: what was saved, and every row that was not, with the
/// reason and what to do. Rows can be added by hand from here.
class ImportReportScreen extends ConsumerStatefulWidget {
  const ImportReportScreen({super.key});

  @override
  ConsumerState<ImportReportScreen> createState() => _ImportReportScreenState();
}

class _ImportReportScreenState extends ConsumerState<ImportReportScreen> {
  ImportRowKind? _tab;

  static const _tabs = [
    ImportRowKind.skipped,
    ImportRowKind.alreadySaved,
    ImportRowKind.possibleDuplicate,
    ImportRowKind.savedWithWarnings,
  ];

  Color _kindColor(SdColors sd, ImportRowKind kind) => switch (kind) {
        ImportRowKind.skipped => sd.absent,
        ImportRowKind.alreadySaved => sd.info,
        ImportRowKind.possibleDuplicate => sd.leave,
        ImportRowKind.savedWithWarnings => sd.leave,
        ImportRowKind.saved => sd.present,
      };

  Future<void> _export(ImportReport report, ImportRowKind kind) async {
    final l10n = AppLocalizations.of(context);
    final table = report.exportTable(
      report.of(kind),
      kindLabel: (k) => importRowKindLabel(l10n, k),
      issueLabel: (i) => rowIssueLabel(l10n, i),
      fixLabel: (c) => importFixLabel(l10n, c),
      leadingHeaders: [l10n.irExcelRow, l10n.irStatus, l10n.irReason, l10n.irWhatToDo],
    );
    final bytes = XlsxStyledWriter.write(
      sheetName: importRowKindLabel(l10n, kind),
      headingLines: [l10n.irTitle, report.sourceName, importRowKindLabel(l10n, kind)],
      header: table.header,
      rows: table.rows,
      types: [XlsxCellType.number, for (var i = 1; i < table.header.length; i++) XlsxCellType.text],
      notes: [l10n.irExportNote],
    );
    final saved = await saveBytesWithDialog(
      fileName: '${p.basenameWithoutExtension(report.sourceName)}-${kind.name}.xlsx',
      bytes: bytes,
      title: l10n.irExport,
    );
    if (saved && mounted) SdToast.show(context, l10n.exported);
  }

  Future<void> _undo(ImportReport report) async {
    final l10n = AppLocalizations.of(context);
    final ok = await SdDialog.confirm(
      context,
      title: l10n.importUndo,
      message: l10n.importUndoConfirm,
      confirmLabel: l10n.importUndo,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(importRepositoryProvider).undo(report.batchId);
    ref.read(studentsRevisionProvider.notifier).state++;
    ref.read(lastImportReportProvider.notifier).state = null;
    if (!mounted) return;
    SdToast.show(context, l10n.importUndone);
    context.go('/students');
  }

  void _close() {
    ref.read(lastImportReportProvider.notifier).state = null;
    context.go('/students');
  }

  void _addByHand(ImportReportEntry e) {
    ref.read(importPrefillProvider.notifier).state = (rowNumber: e.rowNumber, draft: e.row.draft);
    context.go('/students/new?fromImport=1');
  }

  Future<void> _details(ImportReport report, ImportReportEntry e) async {
    final l10n = AppLocalizations.of(context);
    final canAdd = ref.read(permissionCheckerProvider)('students.edit');
    final cells = report.sourceOf(e);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        final sd = SdColors.of(sheet);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, SdSpace.xl),
            children: [
              Row(children: [
                Expanded(child: Text(l10n.importRowLabel(e.rowNumber), style: theme.textTheme.titleLarge)),
                StatusPill(text: importRowKindLabel(l10n, e.kind), color: _kindColor(sd, e.kind)),
              ]),
              const SizedBox(height: SdSpace.md),
              for (final issue in e.problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: SdSpace.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        issue.severity == RowSeverity.error ? Icons.error_outline : Icons.info_outline,
                        size: 18,
                        color: issue.severity == RowSeverity.error ? sd.absent : sd.leave,
                      ),
                      const SizedBox(width: SdSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rowIssueLabel(l10n, issue), style: theme.textTheme.bodyMedium),
                            Text(importFixLabel(l10n, issue.code),
                                style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: SdSpace.xl),
              Text(l10n.irOriginalRow, style: theme.textTheme.titleSmall),
              const SizedBox(height: SdSpace.sm),
              for (final (heading, value) in cells) InfoRow(label: heading, value: value),
              const SizedBox(height: SdSpace.lg),
              Wrap(
                spacing: SdSpace.sm,
                runSpacing: SdSpace.sm,
                children: [
                  SdButton(
                    label: l10n.irCopyRow,
                    icon: Icons.copy_outlined,
                    variant: SdButtonVariant.secondary,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                        text: [
                          l10n.importRowLabel(e.rowNumber),
                          for (final (h, v) in cells)
                            if (v.trim().isNotEmpty) '$h: $v',
                        ].join('\n'),
                      ));
                      if (sheet.mounted) SdToast.show(sheet, l10n.irCopied);
                    },
                  ),
                  if (e.kind == ImportRowKind.skipped && canAdd && !report.resolved.contains(e.rowNumber))
                    SdButton(
                      label: l10n.irAddByHand,
                      icon: Icons.person_add_alt,
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        _addByHand(e);
                      },
                    ),
                  if (e.studentId != null && e.kind != ImportRowKind.skipped)
                    SdButton(
                      label: e.kind == ImportRowKind.alreadySaved ? l10n.irOpenExisting : l10n.irOpenSaved,
                      icon: Icons.open_in_new,
                      variant: SdButtonVariant.secondary,
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        this.context.go('/students/${e.studentId}');
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final report = ref.watch(lastImportReportProvider);
    if (report == null) {
      return SdPage(children: [
        SdEmptyState(
          icon: Icons.inventory_2_outlined,
          title: l10n.irNone,
          message: l10n.irNoneHint,
          action: SdButton(label: l10n.importOpenStudents, onPressed: () => context.go('/students')),
        ),
      ]);
    }
    final tab = _tab ?? _tabs.firstWhere((k) => report.count(k) > 0, orElse: () => ImportRowKind.skipped);
    final list = report.of(tab);

    Widget figure(String label, int value, Color? color) => SizedBox(
          width: 132,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
            ],
          ),
        );

    return SdPage(
      children: [
        Row(children: [
          IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/students')),
          const SizedBox(width: SdSpace.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.irTitle, style: theme.textTheme.headlineSmall),
                Text(report.sourceName, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
              ],
            ),
          ),
          SdButton(label: l10n.irClose, variant: SdButtonVariant.text, onPressed: _close),
        ]),
        const SizedBox(height: SdSpace.lg),
        SdCard(
          child: Wrap(
            spacing: SdSpace.lg,
            runSpacing: SdSpace.lg,
            children: [
              figure(l10n.irRows, report.total, null),
              figure(l10n.irAdded, report.added, sd.present),
              figure(l10n.irUpdated, report.updated, sd.present),
              figure(l10n.irKindSkipped, report.count(ImportRowKind.skipped), sd.absent),
              figure(l10n.irKindAlreadySaved, report.count(ImportRowKind.alreadySaved), sd.info),
              figure(l10n.irKindPossibleDuplicate, report.count(ImportRowKind.possibleDuplicate), sd.leave),
              figure(l10n.irKindWarnings, report.count(ImportRowKind.savedWithWarnings), sd.leave),
            ],
          ),
        ),
        const SizedBox(height: SdSpace.sm),
        Text(l10n.irSummaryNote, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
        const SizedBox(height: SdSpace.lg),
        Wrap(
          spacing: SdSpace.sm,
          runSpacing: SdSpace.sm,
          children: [
            for (final k in _tabs)
              ChoiceChip(
                label: Text('${importRowKindLabel(l10n, k)} (${report.count(k)})'),
                selected: k == tab,
                showCheckmark: false,
                onSelected: (_) => setState(() => _tab = k),
              ),
          ],
        ),
        const SizedBox(height: SdSpace.sm),
        Text(_tabHint(l10n, tab), style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
        const SizedBox(height: SdSpace.md),
        if (list.isEmpty)
          SdCard(child: Text(l10n.irEmptyTab, style: theme.textTheme.bodyMedium))
        else
          SdCard(
            child: Column(
              children: [
                for (final e in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: _kindColor(sd, e.kind).withValues(alpha: 0.12),
                      child: Text(
                        '${e.rowNumber}',
                        style: theme.textTheme.labelMedium?.copyWith(color: _kindColor(sd, e.kind)),
                      ),
                    ),
                    title: Text(e.row.draft.fullName.trim().isEmpty ? l10n.irNoName : e.row.draft.fullName),
                    subtitle: Text(
                      [
                        if ((e.row.draft.identifiers[IdentifierType.grNumber] ?? '').isNotEmpty)
                          '${l10n.idGr} ${e.row.draft.identifiers[IdentifierType.grNumber]}',
                        e.problems.map((i) => rowIssueLabel(l10n, i)).join('; '),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: report.resolved.contains(e.rowNumber)
                        ? StatusPill(text: l10n.irAddedByHand, color: sd.present)
                        : const Icon(Icons.chevron_right),
                    onTap: () => _details(report, e),
                  ),
              ],
            ),
          ),
        const SizedBox(height: SdSpace.lg),
        Wrap(
          spacing: SdSpace.sm,
          runSpacing: SdSpace.sm,
          children: [
            if (list.isNotEmpty)
              SdButton(
                label: l10n.irExport,
                icon: Icons.table_chart_outlined,
                variant: SdButtonVariant.secondary,
                onPressed: () => _export(report, tab),
              ),
            SdButton(label: l10n.importOpenStudents, onPressed: () => context.go('/students')),
            SdButton(label: l10n.importUndo, variant: SdButtonVariant.text, onPressed: () => _undo(report)),
          ],
        ),
      ],
    );
  }

  String _tabHint(AppLocalizations l10n, ImportRowKind k) => switch (k) {
        ImportRowKind.skipped => l10n.irHintSkipped,
        ImportRowKind.alreadySaved => l10n.irHintAlreadySaved,
        ImportRowKind.possibleDuplicate => l10n.irHintPossibleDuplicate,
        ImportRowKind.savedWithWarnings => l10n.irHintWarnings,
        ImportRowKind.saved => '',
      };
}
