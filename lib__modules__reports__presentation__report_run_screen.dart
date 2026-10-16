import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../../platform/reporting/report_dataset.dart';
import '../../../platform/reporting/report_output.dart';
import '../../../platform/reporting/report_pdf_preview.dart';
import '../../students/presentation/student_picker.dart';
import '../../../platform/reporting/report_preview.dart';
import '../../attendance/presentation/division_picker.dart';
import '../../certificates/application/certificates_providers.dart';
import '../../certificates/domain/certificate_models.dart';
import '../../fees/application/fees_providers.dart';
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
  CertificateKind? _certKind;
  bool _overdueOnly = false;
  StudentSort _sort = StudentSort.roll;
  bool _descending = false;
  GenderFilter _gender = GenderFilter.all;
  List<ClassListColumn> _layout = const [];
  bool _fullAadhaar = false;

  bool get _isNameList => widget.kind == ReportKind.classList || widget.kind == ReportKind.master;
  bool get _master => widget.kind == ReportKind.master;
  String get _layoutKey => 'reports.layout.${widget.kind.name}';

  @override
  void initState() {
    super.initState();
    _layout = StudentListLayout.defaults(master: _master);
    if (_isNameList) _loadLayout();
  }

  /// The last column layout used for this report.
  Future<void> _loadLayout() async {
    try {
      final raw = await ref.read(appSettingsRepositoryProvider).getValue(_layoutKey);
      if (mounted) setState(() => _layout = StudentListLayout.decode(raw, master: _master));
    } catch (_) {
      // Keep the standard layout.
    }
  }

  void _setLayout(List<ClassListColumn> layout) {
    setState(() {
      _layout = StudentListLayout.normalise(layout, master: _master);
      if (!_layout.contains(ClassListColumn.aadhaar)) _fullAadhaar = false;
    });
    ref.read(appSettingsRepositoryProvider).setValue(_layoutKey, StudentListLayout.encode(_layout)).ignore();
  }

  bool get _canFullAadhaar => ref.read(permissionCheckerProvider)('students.view_sensitive');

  ReportDataset? _data;
  bool _busy = false;
  final Map<int, String> _filters = {};
  int? _sortColumn;
  bool _ascending = true;

  /// What is shown and exported: the report with on-screen filters and sorting applied.
  ReportDataset? get _view =>
      _data?.arranged(filters: _filters, sortColumn: _sortColumn, ascending: _ascending);

  bool get _needsDivision =>
      widget.kind == ReportKind.register || widget.kind == ReportKind.classList || widget.kind == ReportKind.photoRegister;

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    final fullAadhaar = _isNameList && _fullAadhaar && _canFullAadhaar && _layout.contains(ClassListColumn.aadhaar);
    if (fullAadhaar) {
      final ok = await SdDialog.confirm(
        context,
        title: l10n.reportAadhaarFullConfirmTitle,
        message: l10n.reportAadhaarFullConfirm,
        confirmLabel: l10n.reportAadhaarFullConfirmYes,
        cancelLabel: l10n.cancel,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _data = null;
      _filters.clear();
      _sortColumn = null;
    });
    try {
      final year = ref.read(academicControllerProvider).activeYear;
      if (widget.kind.isFee && year == null && widget.kind != ReportKind.feeDayBook && widget.kind != ReportKind.feeHeads) {
        if (mounted) SdToast.show(context, l10n.feeErrNoYear);
        return;
      }
      final yearId = year?.id ?? '';
      final yearLabel = year?.label ?? '';
      final b = await reportBuilders(ref, l10n);
      final data = switch (widget.kind) {
        ReportKind.register => await b.monthlyRegister(_divisionId!, _month.year, _month.month),
        ReportKind.defaulters => await b.defaulters(from: _from, to: _to, threshold: _threshold, programId: _programId),
        ReportKind.absentees => await b.absentees(_date),
        ReportKind.summary => await b.attendanceSummary(from: _from, to: _to),
        ReportKind.classList => await b.classList(
            _divisionId!,
            _layout,
            sort: _sort,
            descending: _descending,
            gender: _gender,
            fullAadhaar: fullAadhaar,
          ),
        ReportKind.master => await b.studentMaster(
            programId: _programId,
            status: _status,
            show: _layout,
            sort: _sort,
            descending: _descending,
            gender: _gender,
            fullAadhaar: fullAadhaar,
          ),
        ReportKind.photoRegister =>
          await b.photoRegister(_divisionId!, sort: _sort, descending: _descending, gender: _gender),
        ReportKind.certificates => await b.certificateRegister(from: _from, to: _to, kind: _certKind),
        ReportKind.feeDayBook => await feeReports(ref, l10n).dayBook(from: _from, to: _to),
        ReportKind.feeHeads => await feeReports(ref, l10n).headWise(from: _from, to: _to),
        ReportKind.feeClassSummary => await feeReports(ref, l10n).classSummary(yearId, yearLabel),
        ReportKind.feeDefaulters => await feeReports(ref, l10n)
            .defaulters(yearId, yearLabel, programId: _programId, overdueOnly: _overdueOnly),
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
      if (widget.kind == ReportKind.certificates)
        SdSelectField<CertificateKind>(
          label: l10n.certChooseType,
          value: _certKind,
          clearLabel: l10n.certAllTypes,
          emptyText: l10n.certAllTypes,
          options: [for (final k in CertificateKind.values) (k, certificateTitle(l10n, k))],
          onChanged: (v) => setState(() => _certKind = v),
        ),
      if (widget.kind == ReportKind.defaulters ||
          widget.kind == ReportKind.summary ||
          widget.kind == ReportKind.certificates ||
          widget.kind == ReportKind.feeDayBook ||
          widget.kind == ReportKind.feeHeads) ...[
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
      if (widget.kind == ReportKind.feeDefaulters)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.feeOverdueOnly),
          subtitle: Text(l10n.feeOverdueOnlyHint),
          value: _overdueOnly,
          onChanged: (v) => setState(() => _overdueOnly = v),
        ),
      if (widget.kind == ReportKind.defaulters || widget.kind == ReportKind.master || widget.kind == ReportKind.feeDefaulters)
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
      if (_isNameList || widget.kind == ReportKind.photoRegister) ...[
        Row(children: [
          Expanded(
            child: SdSelectField<StudentSort>(
              label: l10n.sortBy,
              value: _sort,
              options: [
                for (final o in const [StudentSort.gr, StudentSort.name, StudentSort.age, StudentSort.roll, StudentSort.gender])
                  (o, studentSortLabel(l10n, o)),
              ],
              onChanged: (v) => setState(() => _sort = v ?? _sort),
            ),
          ),
          const SizedBox(width: SdSpace.sm),
          Expanded(
            child: SdSelectField<bool>(
              label: l10n.orderLabel,
              value: _descending,
              options: [(false, l10n.orderAscending), (true, l10n.orderDescending)],
              onChanged: (v) => setState(() => _descending = v ?? _descending),
            ),
          ),
        ]),
        const SizedBox(height: SdSpace.sm),
        SdSelectField<GenderFilter>(
          label: l10n.fieldGender,
          value: _gender,
          options: [for (final g in GenderFilter.values) (g, genderFilterLabel(l10n, g))],
          onChanged: (v) => setState(() => _gender = v ?? _gender),
        ),
        if (_sort == StudentSort.age)
          Padding(
            padding: const EdgeInsets.only(top: SdSpace.xs),
            child: Text(l10n.reportAgeHint, style: theme.textTheme.bodySmall),
          ),
        if (widget.kind == ReportKind.photoRegister)
          Padding(
            padding: const EdgeInsets.only(top: SdSpace.md),
            child: Text(l10n.reportPhotoRegisterHint, style: theme.textTheme.bodySmall),
          ),
        if (_isNameList) ...[
          const SizedBox(height: SdSpace.md),
          _ColumnChooser(
            layout: _layout,
            available: StudentListLayout.available(master: _master),
            label: (c) => _columnLabel(l10n, c),
            onChanged: _setLayout,
            onReset: () => _setLayout(StudentListLayout.defaults(master: _master)),
          ),
          if (_layout.contains(ClassListColumn.aadhaar)) ...[
            const SizedBox(height: SdSpace.sm),
            if (_canFullAadhaar)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.reportAadhaarFull),
                subtitle: Text(_fullAadhaar ? l10n.reportAadhaarFullHint : l10n.reportAadhaarMaskedHint),
                value: _fullAadhaar,
                onChanged: (v) => setState(() => _fullAadhaar = v),
              )
            else
              Text(l10n.reportAadhaarMaskedHint, style: theme.textTheme.bodySmall),
          ],
        ],
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
                label: l10n.reportPreview,
                icon: Icons.visibility_outlined,
                onPressed: _busy
                    ? null
                    : () => _output(() async {
                          final head = await reportLetterhead(ref);
                          if (!mounted) return;
                          await showReportPdfPreview(context, data, head);
                        }),
              ),
              SdButton(
                label: l10n.reportSavePdf,
                icon: Icons.picture_as_pdf_outlined,
                variant: SdButtonVariant.secondary,
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
              if (!data.pdfOnly)
              SdButton(
                label: l10n.exportExcel,
                icon: Icons.table_chart_outlined,
                variant: SdButtonVariant.text,
                onPressed: _busy
                    ? null
                    : () => _output(() async => ReportOutput.saveExcel(data, await reportLetterhead(ref), title: l10n.exportExcel)),
              ),
              if (!data.pdfOnly)
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
        ClassListColumn.serial => l10n.reportSrNo,
        ClassListColumn.roll => l10n.reportRoll,
        ClassListColumn.name => l10n.fieldName,
        ClassListColumn.code => l10n.studentCode,
        ClassListColumn.gender => l10n.fieldGender,
        ClassListColumn.dateOfBirth => l10n.fieldDateOfBirth,
        ClassListColumn.gr => l10n.idGr,
        ClassListColumn.pen => l10n.idPen,
        ClassListColumn.apaar => l10n.idApaar,
        ClassListColumn.aadhaar => l10n.idAadhaar,
        ClassListColumn.motherName => l10n.reportMotherName,
        ClassListColumn.fatherName => l10n.fieldFatherName,
        ClassListColumn.mobile => l10n.fieldMobile,
        ClassListColumn.category => l10n.fieldCategory,
        ClassListColumn.bloodGroup => l10n.fieldBloodGroup,
        ClassListColumn.status => l10n.studentsFilterStatus,
      };
}

/// Columns of a student list: tick to show, ▲▼ to move. Shown columns come
/// first, in their order; the rest are listed below to switch on.
class _ColumnChooser extends StatelessWidget {
  const _ColumnChooser({
    required this.layout,
    required this.available,
    required this.label,
    required this.onChanged,
    required this.onReset,
  });

  final List<ClassListColumn> layout;
  final List<ClassListColumn> available;
  final String Function(ClassListColumn c) label;
  final ValueChanged<List<ClassListColumn>> onChanged;
  final VoidCallback onReset;

  void _move(int from, int to) {
    final next = [...layout];
    final c = next.removeAt(from);
    next.insert(to, c);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final hidden = available.where((c) => !layout.contains(c)).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: sd.border),
        borderRadius: BorderRadius.circular(SdRadius.md),
      ),
      padding: const EdgeInsets.all(SdSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(l10n.reportColumnsOrder, style: theme.textTheme.titleSmall)),
            TextButton.icon(onPressed: onReset, icon: const Icon(Icons.restart_alt, size: 18), label: Text(l10n.reportColumnsReset)),
          ]),
          Text(l10n.reportColumnsHint, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
          const SizedBox(height: SdSpace.xs),
          for (var i = 0; i < layout.length; i++)
            Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text('${i + 1}.', style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
                ),
                Checkbox(
                  value: true,
                  onChanged: StudentListLayout.fixed.contains(layout[i])
                      ? null
                      : (_) => onChanged([...layout]..removeAt(i)),
                ),
                Expanded(child: Text(label(layout[i]))),
                IconButton(
                  tooltip: l10n.reportColumnUp,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  // Sr. No. stays first.
                  onPressed: i <= 1 || layout[i] == ClassListColumn.serial ? null : () => _move(i, i - 1),
                ),
                IconButton(
                  tooltip: l10n.reportColumnDown,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: i == 0 || i == layout.length - 1 ? null : () => _move(i, i + 1),
                ),
              ],
            ),
          if (hidden.isNotEmpty) ...[
            const Divider(),
            Text(l10n.reportColumnsMore, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
            const SizedBox(height: SdSpace.xs),
            Wrap(
              spacing: SdSpace.sm,
              runSpacing: SdSpace.sm,
              children: [
                for (final c in hidden)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(label(c)),
                    onPressed: () => onChanged([...layout, c]),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
