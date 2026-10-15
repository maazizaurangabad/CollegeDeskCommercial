import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/reporting/report_dataset.dart';
import '../../../platform/reporting/report_output.dart';
import '../../../platform/reporting/report_pdf_preview.dart';
import '../../../platform/reporting/report_preview.dart';
import '../../attendance/presentation/division_picker.dart';
import '../../reports/application/reports_providers.dart';
import '../application/results_providers.dart';
import '../domain/result_models.dart';

const _finalKey = 'final';

/// Results home: choose exam and class, see the result sheet, enter marks,
/// and save or print the sheet.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  String? _examKey;
  String? _divisionId;
  bool _showRank = false;
  bool _showClass = false;
  bool _busy = false;

  Future<ReportDataset?> _sheet(AppLocalizations l10n, List<Exam> exams) async {
    final academic = ref.read(academicControllerProvider);
    final year = academic.activeYear;
    final divisionId = _divisionId;
    if (year == null || divisionId == null) return null;
    final division = academic.divisions.where((d) => d.id == divisionId).firstOrNull;
    if (division == null) return null;
    final program = academic.programs.where((p) => p.id == division.programId).firstOrNull;
    final key = _examKey ?? _finalKey;
    final repo = ref.read(resultRepositoryProvider);
    final r = await repo.classResult(
      divisionId: divisionId,
      programId: division.programId,
      academicYearId: year.id,
      examId: key == _finalKey ? null : key,
    );
    final examName = key == _finalKey ? l10n.resFinalResult : exams.where((e) => e.id == key).firstOrNull?.name ?? '';
    return resultSheetDataset(
      l10n,
      title: examName,
      classLabel: '${program?.name ?? ''} ${division.name}'.trim(),
      yearLabel: year.label,
      columns: r.columns,
      results: r.results,
      rules: await repo.rules(),
      showRank: _showRank,
      showClass: _showClass,
    );
  }

  Future<void> _output(ReportDataset data, String action) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final head = await reportLetterhead(ref);
      switch (action) {
        case 'pdf':
          if (await ReportOutput.savePdf(data, head, title: l10n.reportSavePdf) && mounted) {
            SdToast.show(context, l10n.exported);
          }
        case 'excel':
          if (await ReportOutput.saveExcel(data, head, title: l10n.exportExcel) && mounted) {
            SdToast.show(context, l10n.exported);
          }
        case 'print':
          await ReportOutput.printPdf(data, head);
        case 'preview':
          if (mounted) await showReportPdfPreview(context, data, head);
      }
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final year = ref.watch(academicControllerProvider).activeYear;
    ref.watch(resultsRevisionProvider);

    final header = Row(children: [
      Expanded(child: Text(l10n.navResults, style: theme.textTheme.headlineSmall)),
      IconButton(tooltip: l10n.resSetup, icon: const Icon(Icons.tune_outlined), onPressed: () => context.go('/results/setup')),
    ]);
    if (year == null) {
      return SdPage(children: [header, SdEmptyState(icon: Icons.event_busy, title: l10n.feeErrNoYear, message: '')]);
    }

    return SdPage(children: [
      header,
      const SizedBox(height: SdSpace.lg),
      FutureBuilder<List<Exam>>(
        future: ref.read(resultRepositoryProvider).exams(year.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SdSkeleton(height: 40);
          final exams = snapshot.data!;
          final key = _examKey ?? _finalKey;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
              for (final e in exams)
                ChoiceChip(label: Text(e.name), selected: key == e.id, onSelected: (_) => setState(() => _examKey = e.id)),
              ChoiceChip(
                avatar: const Icon(Icons.emoji_events_outlined, size: 18),
                label: Text(l10n.resFinalResult),
                selected: key == _finalKey,
                onSelected: (_) => setState(() => _examKey = _finalKey),
              ),
            ]),
            const SizedBox(height: SdSpace.md),
            DivisionPicker(divisionId: _divisionId, onChanged: (v) => setState(() => _divisionId = v)),
            const SizedBox(height: SdSpace.md),
            if (_divisionId != null) ...[
              Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
                SdButton(
                  label: l10n.resEnterMarks,
                  icon: Icons.edit_outlined,
                  onPressed: () {
                    final exam = key == _finalKey ? (exams.where((e) => e.countsInFinal).lastOrNull ?? exams.lastOrNull) : null;
                    final examId = exam?.id ?? key;
                    context.go('/results/marks?exam=$examId&division=$_divisionId');
                  },
                ),
                FilterChip(label: Text(l10n.resColClass), selected: _showClass, onSelected: (v) => setState(() => _showClass = v)),
                FilterChip(label: Text(l10n.resColRank), selected: _showRank, onSelected: (v) => setState(() => _showRank = v)),
              ]),
              const SizedBox(height: SdSpace.lg),
              FutureBuilder<ReportDataset?>(
                future: _sheet(l10n, exams),
                builder: (context, snap) {
                  if (snap.hasError) return Text(resultErrorMessage(l10n, snap.error!));
                  if (snap.connectionState != ConnectionState.done) return const SdSkeleton(height: 240);
                  final data = snap.data;
                  if (data == null || data.rows.isEmpty) {
                    return SdEmptyState(icon: Icons.groups_outlined, title: l10n.resNoStudents, message: '');
                  }
                  if (data.columns.length - 6 - (_showClass ? 1 : 0) - (_showRank ? 1 : 0) <= 0) {
                    return SdEmptyState(
                      icon: Icons.menu_book_outlined,
                      title: l10n.resNoSubjects,
                      message: l10n.resNoSubjectsHint,
                      action: SdButton(label: l10n.resSetup, onPressed: () => context.go('/results/setup')),
                    );
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
                      SdButton(
                        label: l10n.reportPreview,
                        icon: Icons.visibility_outlined,
                        onPressed: _busy ? null : () => _output(data, 'preview'),
                      ),
                      SdButton(
                        label: l10n.reportSavePdf,
                        icon: Icons.picture_as_pdf_outlined,
                        variant: SdButtonVariant.secondary,
                        onPressed: _busy ? null : () => _output(data, 'pdf'),
                      ),
                      SdButton(
                        label: l10n.exportExcel,
                        icon: Icons.table_chart_outlined,
                        variant: SdButtonVariant.secondary,
                        onPressed: _busy ? null : () => _output(data, 'excel'),
                      ),
                      SdButton(
                        label: l10n.resPrint,
                        icon: Icons.print_outlined,
                        variant: SdButtonVariant.secondary,
                        onPressed: _busy ? null : () => _output(data, 'print'),
                      ),
                    ]),
                    const SizedBox(height: SdSpace.md),
                    ReportPreview(data: data),
                    for (final n in data.notes)
                      Padding(
                        padding: const EdgeInsets.only(top: SdSpace.sm),
                        child: Text(n, style: theme.textTheme.bodySmall),
                      ),
                  ]);
                },
              ),
            ],
          ]);
        },
      ),
    ]);
  }
}
