import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/startup/app_bootstrap.dart';
import '../../../core/files/csv.dart';
import '../../../core/files/save_file.dart';
import '../../../core/files/xlsx.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/data_providers.dart';
import '../application/students_providers.dart';
import '../domain/student_models.dart';
import '../import/import_fields.dart';
import '../import/import_labels.dart';
import '../import/import_planner.dart';
import '../import/import_report.dart';
import '../import/import_repository.dart';
import 'student_labels.dart';

enum _Step { pick, configure, preview, done }

/// Excel / CSV import: choose file -> match columns -> check rows -> import.
class StudentImportScreen extends ConsumerStatefulWidget {
  const StudentImportScreen({super.key});

  @override
  ConsumerState<StudentImportScreen> createState() => _StudentImportScreenState();
}

class _StudentImportScreenState extends ConsumerState<StudentImportScreen> {
  _Step _step = _Step.pick;
  bool _busy = false;
  String? _message;

  String _fileName = '';
  List<int> _bytes = const [];
  bool _isCsv = false;
  List<String> _sheetNames = const [];
  int _sheetIndex = 0;
  List<List<String>> _rows = const [];
  int _headerRow = 0;
  ColumnMapping _mapping = [];
  final ImportOptions _options = ImportOptions();
  String? _programForAll;
  List<ImportTemplate> _templates = const [];
  ImportPlan? _plan;
  ImportResult? _result;

  List<String> get _headers => _rows.isEmpty ? const [] : _rows[_headerRow];
  List<List<String>> get _dataRows => _rows.length > _headerRow + 1 ? _rows.sublist(_headerRow + 1) : const [];
  bool get _hasClassColumn => _mapping.contains(fieldId(ImportField.className));
  bool get _hasFullName => _mapping.contains(fieldId(ImportField.fullName));

  Future<void> _pickFile() async {
    final l10n = AppLocalizations.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'xls'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    final ext = p.extension(path).toLowerCase();
    // A new import replaces the last report.
    ref.read(lastImportReportProvider.notifier).state = null;
    if (ext == '.xls') {
      setState(() => _message = l10n.importXlsWarning);
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      _templates = await ref.read(importRepositoryProvider).templates();
      setState(() {
        _fileName = p.basename(path);
        _bytes = bytes;
        _isCsv = ext == '.csv';
        _sheetNames = _isCsv ? const ['CSV'] : XlsxReader.sheetNames(bytes);
        _message = null;
      });
      _loadSheet(0);
      setState(() => _step = _Step.configure);
    } catch (_) {
      setState(() => _message = l10n.importReadFailed);
    }
  }

  void _loadSheet(int index) {
    final rows = _isCsv ? CsvReader.parse(_bytes) : XlsxReader.readSheet(_bytes, index).rows;
    setState(() {
      _sheetIndex = index;
      _rows = rows;
      _setHeaderRow(guessHeaderRow(rows));
    });
  }

  void _setHeaderRow(int row) {
    _headerRow = row.clamp(0, _rows.isEmpty ? 0 : _rows.length - 1);
    _mapping = guessMapping(_headers).map(fieldId).toList();
    // A saved matching wins where it knows a heading.
    for (final t in _templates) {
      final known = _headers.where((h) => t.columns.containsKey(normalizeHeader(h))).length;
      if (known >= (_headers.where((h) => h.trim().isNotEmpty).length / 2)) _applyTemplate(t);
    }
  }

  void _applyTemplate(ImportTemplate t) {
    for (var i = 0; i < _headers.length; i++) {
      final id = t.columns[normalizeHeader(_headers[i])];
      if (id != null) _mapping[i] = id;
    }
  }

  void _setColumn(int index, String id) {
    setState(() {
      // A field can only come from one column.
      if (id != fieldId(ImportField.ignore)) {
        for (var i = 0; i < _mapping.length; i++) {
          if (_mapping[i] == id) _mapping[i] = fieldId(ImportField.ignore);
        }
      }
      _mapping[index] = id;
    });
  }

  Future<void> _saveTemplate() async {
    final l10n = AppLocalizations.of(context);
    final name = await SdDialog.prompt(
      context,
      title: l10n.importTemplateSave,
      label: l10n.importTemplateName,
      confirmLabel: l10n.save,
      cancelLabel: l10n.cancel,
      initial: p.basenameWithoutExtension(_fileName),
    );
    if (name == null || name.trim().isEmpty) return;
    final columns = <String, String>{
      for (var i = 0; i < _headers.length; i++)
        if (_headers[i].trim().isNotEmpty) normalizeHeader(_headers[i]): _mapping[i],
    };
    await ref.read(importRepositoryProvider).saveTemplate(ImportTemplate(name.trim(), columns));
    _templates = await ref.read(importRepositoryProvider).templates();
    if (mounted) SdToast.show(context, l10n.importTemplateSaved);
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final students = ref.read(studentRepositoryProvider);
      final index = await students.importIndex();
      final planner = ImportPlanner(
        academic: ref.read(academicControllerProvider),
        existing: ExistingData(
          identifierOwners: index.identifierOwners,
          aadhaarOwners: index.aadhaarOwners,
          nameDob: index.nameDob,
          rollsByDivision: index.rollsByDivision,
        ),
        extraFields: await ref.read(extraFieldsProvider.future),
        fingerprint: ref.read(startupStateProvider).fieldCipher.fingerprint,
      );
      if (_hasClassColumn) _options.fixedDivisionId = null;
      _options.motherRequired = await ref.read(motherRequiredProvider.future);
      final plan = await planner.plan(_dataRows, _mapping, _options, firstRowNumber: _headerRow + 2);
      setState(() {
        _plan = plan;
        _step = _Step.preview;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // A safety copy first (when a backup password is set).
      await AppBootstrap.runBeforeBackup(ref.read(startupStateProvider), 'import').catchError((Object _) {});
      final result = await ref.read(importRepositoryProvider).commitStudents(
            plan: _plan!,
            options: _options,
            sourceName: _fileName,
            extraFields: await ref.read(extraFieldsProvider.future),
            activeYearId: ref.read(academicControllerProvider).activeYear?.id,
          );
      ref.read(studentsRevisionProvider.notifier).state++;
      if (_plan!.missingPlacements.isNotEmpty) {
        await ref.read(academicControllerProvider.notifier).reload();
      }
      // The report stays until it is closed or another import starts.
      ref.read(lastImportReportProvider.notifier).state = ImportReport.from(
        plan: _plan!,
        result: result,
        sourceName: _fileName,
        headers: _headers,
        mapping: _mapping,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _Step.done;
      });
      context.go('/students/import-report');
    } catch (e) {
      final detail = e is ImportRowFailure
          ? '${l10n.importRowLabel(e.rowNumber)}: ${studentErrorMessage(l10n, e.cause)}'
          : l10n.saveFailed;
      setState(() => _message = '${l10n.importFailedRow}\n$detail');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadErrors() async {
    final l10n = AppLocalizations.of(context);
    final rows = _plan!.rows.where((r) => r.severity == RowSeverity.error).toList();
    final bytes = XlsxWriter.write(
      sheetName: 'Errors',
      header: ['Row', 'Problem', ..._headers],
      rows: [
        for (final r in rows)
          [
            '${r.rowNumber}',
            r.issues.where((i) => i.severity == RowSeverity.error).map((i) => rowIssueLabel(l10n, i)).join('; '),
            ...r.source,
          ],
      ],
    );
    final saved = await saveBytesWithDialog(
      fileName: '${p.basenameWithoutExtension(_fileName)}-errors.xlsx',
      bytes: bytes,
      title: l10n.importDownloadErrors,
    );
    if (saved && mounted) SdToast.show(context, l10n.exported);
  }

  Future<void> _undo() async {
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
    await ref.read(importRepositoryProvider).undo(_result!.batchId);
    ref.read(studentsRevisionProvider.notifier).state++;
    if (mounted) {
      SdToast.show(context, l10n.importUndone);
      context.go('/students');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SdPage(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.back,
              icon: const Icon(Icons.arrow_back),
              onPressed: _busy ? null : () => context.go('/students'),
            ),
            const SizedBox(width: SdSpace.xs),
            Expanded(child: Text(l10n.importStudentsTitle, style: theme.textTheme.headlineSmall)),
          ],
        ),
        const SizedBox(height: SdSpace.lg),
        if (_message != null) ...[
          SdCard(child: Text(_message!, style: theme.textTheme.bodyMedium?.copyWith(color: SdColors.of(context).absent))),
          const SizedBox(height: SdSpace.lg),
        ],
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: SdSpace.sm),
          Text(_step == _Step.preview ? l10n.importImporting : l10n.importChecking, style: theme.textTheme.bodySmall),
          const SizedBox(height: SdSpace.lg),
        ],
        ...switch (_step) {
          _Step.pick => _pickStep(l10n),
          _Step.configure => _configureStep(l10n),
          _Step.preview => _previewStep(l10n),
          _Step.done => _doneStep(l10n),
        },
      ],
    );
  }

  List<Widget> _pickStep(AppLocalizations l10n) => [
        Text(l10n.importIntro),
        const SizedBox(height: SdSpace.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: SdButton(label: l10n.importChooseFile, icon: Icons.upload_file_outlined, onPressed: _pickFile),
        ),
      ];

  List<Widget> _configureStep(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final academic = ref.watch(academicControllerProvider);
    final extra = ref.watch(extraFieldsProvider).valueOrNull ?? const <ExtraFieldDefinition>[];
    final options = mappingOptions(l10n, extra);
    final data = _dataRows;
    String sample(int col) {
      for (final r in data.take(20)) {
        if (col < r.length && r[col].trim().isNotEmpty) return r[col];
      }
      return '';
    }

    return [
      SdSection(
        title: _fileName,
        child: SdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_sheetNames.length > 1)
                SdSelectField<int>(
                  label: l10n.importSheet,
                  value: _sheetIndex,
                  options: [for (var i = 0; i < _sheetNames.length; i++) (i, _sheetNames[i])],
                  onChanged: (v) => _loadSheet(v ?? 0),
                ),
              SdSelectField<int>(
                label: l10n.importHeaderRow,
                value: _headerRow,
                options: [
                  for (var i = 0; i < (_rows.length < 15 ? _rows.length : 15); i++)
                    (i, '${i + 1}: ${_rows[i].where((c) => c.isNotEmpty).take(4).join(' | ')}'),
                ],
                onChanged: (v) => setState(() => _setHeaderRow(v ?? 0)),
              ),
              Text(l10n.importRowsFound(data.where((r) => r.any((c) => c.trim().isNotEmpty)).length),
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      const SizedBox(height: SdSpace.xl),
      SdSection(
        title: l10n.importColumns,
        trailing: _templates.isEmpty
            ? null
            : PopupMenuButton<ImportTemplate>(
                tooltip: l10n.importTemplateUse,
                icon: const Icon(Icons.bookmarks_outlined),
                onSelected: (t) => setState(() => _applyTemplate(t)),
                itemBuilder: (_) => [for (final t in _templates) PopupMenuItem(value: t, child: Text(t.name))],
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.importColumnsHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: SdSpace.md),
            SdCard(
              child: Column(
                children: [
                  for (var i = 0; i < _headers.length; i++)
                    if (_headers[i].trim().isNotEmpty || sample(i).isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: SdSpace.md, right: SdSpace.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_headers[i].isEmpty ? '—' : _headers[i], style: theme.textTheme.titleSmall),
                                  Text('${l10n.importSample}: ${sample(i)}',
                                      style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: SdSelectField<String>(
                              label: '',
                              value: _mapping[i],
                              options: options,
                              onChanged: (v) => _setColumn(i, v ?? fieldId(ImportField.ignore)),
                            ),
                          ),
                        ],
                      ),
                ],
              ),
            ),
            const SizedBox(height: SdSpace.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: SdButton(
                label: l10n.importTemplateSave,
                icon: Icons.bookmark_add_outlined,
                variant: SdButtonVariant.text,
                onPressed: _saveTemplate,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: SdSpace.xl),
      if (_hasFullName) ...[
        SdSection(
          title: l10n.importNames,
          child: SdCard(
            child: SdSelectField<NameOrder>(
              label: l10n.importNames,
              value: _options.nameOrder,
              options: [
                (NameOrder.firstMiddleLast, l10n.importNameFirst),
                (NameOrder.surnameFirst, l10n.importNameSurname),
              ],
              onChanged: (v) => setState(() => _options.nameOrder = v ?? NameOrder.firstMiddleLast),
            ),
          ),
        ),
        const SizedBox(height: SdSpace.xl),
      ],
      SdSection(
        title: l10n.importPlacement,
        child: SdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_hasClassColumn)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.importCreateMissing),
                  value: _options.createMissingPlacements,
                  onChanged: (v) => setState(() => _options.createMissingPlacements = v),
                )
              else if (academic.activeYear == null)
                Text(l10n.placementNeedsYear)
              else ...[
                Text(l10n.importAllInto, style: theme.textTheme.bodySmall),
                const SizedBox(height: SdSpace.md),
                SdSelectField<String>(
                  label: l10n.fieldClass,
                  value: _programForAll,
                  options: [for (final p in academic.programs) (p.id, p.name)],
                  clearLabel: l10n.importNoPlacement,
                  onChanged: (v) => setState(() {
                    _programForAll = v;
                    _options.fixedDivisionId = null;
                  }),
                ),
                if (_programForAll != null)
                  SdSelectField<String>(
                    label: l10n.fieldDivision,
                    value: _options.fixedDivisionId,
                    options: [for (final d in academic.divisionsOf(_programForAll!)) (d.id, d.name)],
                    onChanged: (v) => setState(() => _options.fixedDivisionId = v),
                  ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: SdSpace.xl),
      SdSection(
        title: l10n.importExisting,
        child: SdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.importExistingHint, style: theme.textTheme.bodySmall),
              const SizedBox(height: SdSpace.md),
              SdSelectField<ExistingPolicy>(
                label: l10n.importExisting,
                value: _options.existing,
                options: [
                  (ExistingPolicy.skip, l10n.importSkipExisting),
                  (ExistingPolicy.fillEmpty, l10n.importFillExisting),
                ],
                onChanged: (v) => setState(() => _options.existing = v ?? ExistingPolicy.skip),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: SdSpace.xl),
      Row(
        children: [
          SdButton(
            label: l10n.importAnother,
            variant: SdButtonVariant.text,
            onPressed: _busy ? null : () => setState(() => _step = _Step.pick),
          ),
          const Spacer(),
          SdButton(label: l10n.importCheck, icon: Icons.fact_check_outlined, onPressed: _busy ? null : _check),
        ],
      ),
      const SizedBox(height: SdSpace.xxl),
    ];
  }

  List<Widget> _previewStep(AppLocalizations l10n) {
    final plan = _plan!;
    final sd = SdColors.of(context);
    final importable = plan.rows.where((r) => r.severity != RowSeverity.error && r.existingStudentId == null).length;
    final problems = plan.rows.where((r) => r.issues.isNotEmpty).take(300).toList();
    return [
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth < 560 ? 2 : 4;
        final width = (constraints.maxWidth - SdSpace.md * (columns - 1)) / columns;
        return Wrap(
          spacing: SdSpace.md,
          runSpacing: SdSpace.md,
          children: [
            SizedBox(width: width, child: SdStatTile(label: l10n.importOk, value: '${plan.count(RowSeverity.ok)}', accent: sd.present)),
            SizedBox(width: width, child: SdStatTile(label: l10n.importWarnings, value: '${plan.count(RowSeverity.warning)}', accent: sd.leave)),
            SizedBox(width: width, child: SdStatTile(label: l10n.importErrors, value: '${plan.count(RowSeverity.error)}', accent: sd.absent)),
            SizedBox(width: width, child: SdStatTile(label: l10n.importAlready, value: '${plan.existingCount}')),
          ],
        );
      }),
      const SizedBox(height: SdSpace.xl),
      if (plan.missingPlacements.isNotEmpty) ...[
        SdCard(
          child: Text(
            '${l10n.importWillCreate} ${plan.missingPlacements.map((p) => '${p.$1} ${p.$2}').join(', ')}',
          ),
        ),
        const SizedBox(height: SdSpace.xl),
      ],
      if (problems.isNotEmpty)
        SdSection(
          title: l10n.importProblemRows,
          trailing: plan.count(RowSeverity.error) > 0
              ? SdButton(
                  label: l10n.importDownloadErrors,
                  icon: Icons.download_outlined,
                  variant: SdButtonVariant.text,
                  onPressed: _downloadErrors,
                )
              : null,
          child: SdCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < problems.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: Icon(
                      problems[i].severity == RowSeverity.error ? Icons.error_outline : Icons.info_outline,
                      color: problems[i].severity == RowSeverity.error ? sd.absent : sd.leave,
                    ),
                    title: Text('${l10n.importRowLabel(problems[i].rowNumber)} · ${problems[i].draft.fullName}'),
                    subtitle: Text(problems[i].issues.map((x) => rowIssueLabel(l10n, x)).join('\n')),
                  ),
                ],
              ],
            ),
          ),
        ),
      const SizedBox(height: SdSpace.xl),
      Row(
        children: [
          SdButton(
            label: l10n.back,
            variant: SdButtonVariant.text,
            onPressed: _busy ? null : () => setState(() => _step = _Step.configure),
          ),
          const Spacer(),
          SdButton(
            label: importable == 0 && plan.existingCount == 0 ? l10n.importNothing : l10n.importNowCount(importable),
            icon: Icons.check,
            onPressed: _busy || (importable == 0 && plan.existingCount == 0) ? null : _import,
          ),
        ],
      ),
    ];
  }

  List<Widget> _doneStep(AppLocalizations l10n) {
    final r = _result!;
    return [
      SdEmptyState(
        icon: Icons.task_alt,
        title: l10n.importDone,
        message: l10n.importSummary(r.added, r.updated, r.skipped),
        action: Wrap(
          spacing: SdSpace.sm,
          children: [
            SdButton(label: l10n.importOpenStudents, onPressed: () => context.go('/students')),
            SdButton(label: l10n.importUndo, variant: SdButtonVariant.text, onPressed: _undo),
          ],
        ),
      ),
    ];
  }
}
