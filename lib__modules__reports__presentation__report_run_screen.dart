import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/reporting/report_dataset.dart';
import '../../../platform/reporting/report_output.dart';
import '../../../platform/reporting/report_preview.dart';
import '../../attendance/presentation/division_picker.dart';
import '../../students/domain/student_models.dart';
import '../../students/presentation/student_labels.dart';
import '../application/report_builders.dart';
import '../application/reports_providers.dart';
import 'report_kinds.dart';

/// Options for one report, then the report on screen with PDF, print and Excel.
class ReportRunScreen extends ConsumerStatefulWidget {
  const ReportRunScreen({super.key, required this.kind});

  final ReportKind kind;

  @override
  ConsumerState<ReportRunScreen> createState() => _ReportRunScreenState();
}

class _ReportRunScreenState extends ConsumerState<ReportRunScreen> {
  final _now = DateTime.now();
  String? _divisionId;
  late DateTime _month = DateTime(_now.year, _now.month);
  late DateTime _date = _now;
  late DateTime _from = DateTime(_now.year, _now.month);
  late DateTime _to = _now;
  double _threshold = 75;
  String? _programId;
  StudentStatus? _status = StudentStatus.active;
  final Set<ClassListColumn> _columns = {ClassListColumn.gender, ClassListColumn.dateOfBirth, ClassListColumn.gr, ClassListColumn.mobile};

  ReportDataset? _data;
  bool _busy = false;
  final Map<int, String> _filters = {};
  int? _sortColumn;
  bool _ascending = true;

  /// What is shown and exported: the report with on-screen filters and sorting applied.
  ReportDataset? get _view =>
      _data?.arranged(filters: _filters, sortColumn: _sortColumn, ascending: _ascending);

  bool get _needsDivision => widget.kind == ReportKind.register || widget.kind == ReportKind.classList;

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _data = null;
      _filters.clear();
      _sortColumn = null;
    });
    try {
      final b = await reportBuilders(ref, l10n);
      final data = switch (widget.kind) {
        ReportKind.register => await b.monthlyRegister(_divisionId!, _month.year, _month.month),
        ReportKind.defaulters => await b.defaulters(from: _from, to: _to, threshold: _threshold, programId: _programId),
        ReportKind.absentees => await b.absentees(_date),
        ReportKind.summary => await b.attendanceSummary(from: _from, to: _to),
        ReportKind.classList => await b.classList(_divisionId!, _columns),
        ReportKind.master => await b.studentMaster(programId: _programId, status: _status, show: _columns),
      };
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _output(Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(_now.year + 1, 12, 31),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final academic = ref.watch(academicControllerProvider);
    final dates = DateFormat('d MMM y');
    final data = _view;
    final canRun = !_needsDivision || _divisionId != null;

    Widget dateTile(String label, DateTime value, ValueChanged<DateTime> onChanged) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(label),
          subtitle: Text(dates.format(value)),
          onTap: () async {
            final picked = await _pick(value);
            if (picked != null) setState(() => onChanged(picked));
          },
        );

    final options = <Widget>[
      if (_needsDivision) DivisionPicker(divisionId: _divisionId, onChanged: (v) => setState(() => _divisionId = v)),
      if (widget.kind == ReportKind.register)
        Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
          ),
          Expanded(child: Text(DateFormat('MMMM y').format(_month), textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
          ),
        ]),
      if (widget.kind == ReportKind.absentees) dateTile(l10n.attendanceDate, _date, (d) => _date = d),
      if (widget.kind == ReportKind.defaulters || widget.kind == ReportKind.summary) ...[
        dateTile(l10n.reportFrom, _from, (d) => _from = d),
        dateTile(l10n.reportTo, _to, (d) => _to = d),
      ],
      if (widget.kind == ReportKind.defaulters)
        SdSelectField<double>(
          label: l10n.reportThreshold,
          value: _threshold,
          options: [for (final t in const [50.0, 60.0, 65.0, 70.0, 75.0, 80.0, 85.0]) (t, l10n.reportBelowPercent(t.toStringAsFixed(0)))],
          onChanged: (v) => setState(() => _threshold = v ?? 75),
        ),
      if (widget.kind == ReportKind.defaulters || widget.kind == ReportKind.master)
        SdSelectField<String>(
          label: l10n.fieldClass,
          value: _programId,
          clearLabel: l10n.studentsFilterAll,
          emptyText: l10n.studentsFilterAll,
          options: [for (final p in academic.programs) (p.id, p.name)],
          onChanged: (v) => setState(() => _programId = v),
        ),
      if (widget.kind == ReportKind.master)
        SdSelectField<StudentStatus>(
          label: l10n.studentsFilterStatus,
          value: _status,
          clearLabel: l10n.studentsFilterAll,
          emptyText: l10n.studentsFilterAll,
          options: [for (final s in StudentStatus.values) (s, studentStatusLabel(l10n, s))],
          onChanged: (v) => setState(() => _status = v),
        ),
      if (widget.kind == ReportKind.classList || widget.kind == ReportKind.master) ...[
        Text(l10n.reportColumns, style: theme.textTheme.bodySmall),
        const SizedBox(height: SdSpace.sm),
        Wrap(
          spacing: SdSpace.sm,
          runSpacing: SdSpace.sm,
          children: [
            for (final c in ClassListColumn.values)
              FilterChip(
                label: Text(_columnLabel(l10n, c)),
                selected: _columns.contains(c),
                onSelected: (on) => setState(() {
                  if (on) {
                    _columns.add(c);
                  } else {
                    _columns.remove(c);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: SdSpace.md),
      ],
    ];

    return SdPage(
      children: [
        Row(children: [
          IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/reports')),
          const SizedBox(width: SdSpace.xs),
          Expanded(child: Text(widget.kind.title(l10n), style: theme.textTheme.headlineSmall)),
        ]),
        const SizedBox(height: SdSpace.lg),
        SdCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: options)),
        const SizedBox(height: SdSpace.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: SdButton(label: l10n.reportShow, icon: Icons.play_arrow, onPressed: _busy || !canRun ? null : _run),
        ),
        if (_busy) ...[const SizedBox(height: SdSpace.lg), const LinearProgressIndicator()],
        if (data != null) ...[
          const SizedBox(height: SdSpace.xl),
          Wrap(
            spacing: SdSpace.sm,
            runSpacing: SdSpace.sm,
            children: [
              SdButton(
                label: l10n.reportSavePdf,
                icon: Icons.picture_as_pdf_outlined,
                onPressed: _busy
                    ? null
                    : () => _output(() async {
                          final saved = await ReportOutput.savePdf(data, await reportLetterhead(ref), title: l10n.reportSavePdf);
                          if (saved && mounted) SdToast.show(context, l10n.exported);
                        }),
              ),
              if (Platform.isAndroid)
                SdButton(
                  label: l10n.reportShare,
                  icon: Icons.share_outlined,
                  variant: SdButtonVariant.secondary,
                  onPressed: _busy
                      ? null
                      : () => _output(() async => ReportOutput.sharePdf(data, await reportLetterhead(ref), title: l10n.reportShare)),
                ),
              SdButton(
                label: l10n.reportPrint,
                icon: Icons.print_outlined,
                variant: SdButtonVariant.secondary,
                onPressed: _busy ? null : () => _output(() async => ReportOutput.printPdf(data, await reportLetterhead(ref))),
              ),
              SdButton(
                label: l10n.exportExcel,
                icon: Icons.table_chart_outlined,
                variant: SdButtonVariant.text,
                onPressed: _busy
                    ? null
                    : () => _output(() async => ReportOutput.saveExcel(data, await reportLetterhead(ref), title: l10n.exportExcel)),
              ),
              SdButton(
                label: l10n.exportCsv,
                variant: SdButtonVariant.text,
                onPressed: _busy ? null : () => _output(() async => ReportOutput.saveCsv(data, title: l10n.exportCsv)),
              ),
            ],
          ),
          const SizedBox(height: SdSpace.lg),
          if (_data!.filterColumns.isNotEmpty) ...[
            Wrap(
              spacing: SdSpace.sm,
              runSpacing: SdSpace.sm,
              children: [
                for (final col in _data!.filterColumns)
                  if (col < _data!.columns.length)
                    ActionChip(
                      avatar: Icon(_filters.containsKey(col) ? Icons.filter_alt : Icons.filter_alt_outlined, size: 18),
                      label: Text('${_data!.columns[col].label}: ${_filters[col] ?? l10n.studentsFilterAll}'),
                      onPressed: () async {
                        final picked = await SdSheet.show<(String?,)>(
                          context,
                          title: _data!.columns[col].label,
                          builder: (sheet) => ListView(shrinkWrap: true, children: [
                            ListTile(title: Text(l10n.studentsFilterAll), onTap: () => Navigator.of(sheet).pop((null,))),
                            for (final v in _data!.valuesOf(col))
                              ListTile(title: Text(v), onTap: () => Navigator.of(sheet).pop((v,))),
                          ]),
                        );
                        if (picked == null) return;
                        setState(() {
                          if (picked.$1 == null) {
                            _filters.remove(col);
                          } else {
                            _filters[col] = picked.$1!;
                          }
                        });
                      },
                    ),
                if (_filters.isNotEmpty || _sortColumn != null)
                  SdButton(
                    label: l10n.reportClearFilters,
                    variant: SdButtonVariant.text,
                    onPressed: () => setState(() {
                      _filters.clear();
                      _sortColumn = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: SdSpace.md),
          ],
          if (data.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: SdSpace.sm),
              child: Text(data.subtitle.join(' · '), style: theme.textTheme.titleSmall),
            ),
          if (data.dataRowCount == 0)
            SdEmptyState(icon: Icons.inbox_outlined, title: l10n.reportEmpty, message: '')
          else
            ReportPreview(
              data: data,
              moreText: l10n.reportPreviewMore,
              sortColumn: _sortColumn,
              ascending: _ascending,
              onSort: (i) => setState(() {
                if (_sortColumn == i) {
                  _ascending = !_ascending;
                } else {
                  _sortColumn = i;
                  _ascending = true;
                }
              }),
            ),
          Text(l10n.reportSortHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: SdSpace.xxl),
        ],
      ],
    );
  }

  String _columnLabel(AppLocalizations l10n, ClassListColumn c) => switch (c) {
        ClassListColumn.gender => l10n.fieldGender,
        ClassListColumn.dateOfBirth => l10n.fieldDateOfBirth,
        ClassListColumn.gr => l10n.idGr,
        ClassListColumn.pen => l10n.idPen,
        ClassListColumn.apaar => l10n.idApaar,
        ClassListColumn.mobile => l10n.fieldMobile,
        ClassListColumn.category => l10n.fieldCategory,
        ClassListColumn.bloodGroup => l10n.fieldBloodGroup,
      };
}
