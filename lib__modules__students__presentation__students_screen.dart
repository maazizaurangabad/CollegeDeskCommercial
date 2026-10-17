import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../platform/staff/staff_providers.dart';
import '../../../platform/staff/staff_models.dart';
import '../../../core/files/csv.dart';
import '../../../core/files/save_file.dart';
import '../../../core/files/xlsx_styled.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/academic/academic_models.dart';
import '../../../platform/data/data_providers.dart';
import '../application/students_providers.dart';
import '../domain/student_models.dart';
import 'student_labels.dart';
import 'student_picker.dart';

class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _programId;
  String? _divisionId;
  StudentStatus? _status = StudentStatus.active;
  Future<List<StudentListItem>>? _future;
  List<StudentListItem> _shown = const [];

  /// null: roll order when a class is chosen, otherwise by name.
  StudentSort? _sort;
  bool _selecting = false;
  final Set<String> _selected = {};
  bool _working = false;

  StudentSort get _effectiveSort => _sort ?? (_programId != null ? StudentSort.roll : StudentSort.name);

  void _endSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  Future<void> _batch(String action) async {
    final l10n = AppLocalizations.of(context);
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final repo = ref.read(studentRepositoryProvider);
    try {
      if (action == 'bin') {
        final ok = await SdDialog.confirm(
          context,
          title: l10n.batchBinTitle(ids.length),
          message: l10n.batchBinBody,
          confirmLabel: l10n.batchBin,
          cancelLabel: l10n.cancel,
          destructive: true,
        );
        if (!ok || !mounted) return;
        setState(() => _working = true);
        final n = await repo.moveManyToRecycleBin(ids);
        if (mounted) SdToast.show(context, l10n.batchBinDone(n));
      } else {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
          helpText: l10n.batchLeftDate,
        );
        if (date == null || !mounted) return;
        final reason = await SdDialog.prompt(
          context,
          title: l10n.batchLeftTitle(ids.length),
          label: l10n.batchLeftReason,
          confirmLabel: l10n.batchLeft,
          cancelLabel: l10n.cancel,
        );
        if (reason == null || !mounted) return;
        setState(() => _working = true);
        final n = await repo.markManyLeft(ids, date: date, reason: reason);
        if (mounted) SdToast.show(context, l10n.batchLeftDone(n));
      }
      ref.read(studentsRevisionProvider.notifier).state++;
      if (mounted) _endSelection();
    } catch (e) {
      if (mounted) SdToast.show(context, studentErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _export({required bool excel}) async {
    final l10n = AppLocalizations.of(context);
    final labels = await ref.read(academicRepositoryProvider).divisionLabels();
    final rows = await ref.read(studentRepositoryProvider).exportRows(_shown, labels);
    final header = [
      l10n.studentCode,
      l10n.fieldFirstName,
      l10n.fieldMiddleName,
      l10n.fieldLastName,
      l10n.sectionPlacement,
      l10n.fieldRollNumber,
      l10n.fieldGender,
      l10n.fieldDateOfBirth,
      l10n.idGr,
      l10n.idPen,
      l10n.idApaar,
      l10n.idSaral,
      l10n.fieldMobile,
      l10n.fieldCategory,
      l10n.fieldBloodGroup,
      l10n.studentsFilterStatus,
    ];
    final org = ref.read(activeOrganizationProvider);
    final bytes = excel
        ? XlsxStyledWriter.write(
            sheetName: l10n.studentsTitle,
            headingLines: [org.name, l10n.studentsTitle, l10n.studentsCount(rows.length)],
            header: header,
            rows: rows,
            types: [
              for (var i = 0; i < header.length; i++)
                i == 5 ? XlsxCellType.number : (i == 7 ? XlsxCellType.date : XlsxCellType.text),
            ],
            landscape: true,
            brandColor: org.brandColor.toARGB32(),
          )
        : CsvReader.write(header, rows);
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final saved = await saveBytesWithDialog(
      fileName: 'students-$stamp.${excel ? 'xlsx' : 'csv'}',
      bytes: bytes,
      title: excel ? l10n.exportExcel : l10n.exportCsv,
    );
    if (saved && mounted) SdToast.show(context, l10n.exported);
  }
  String? _futureKey;

  /// Reloads only when the search, filters, year or student data change.
  Future<List<StudentListItem>> _load(String? yearId, int revision) {
    final key = '$_query|$_status|$yearId|$revision';
    if (_future == null || key != _futureKey) {
      _futureKey = key;
      _future = ref.read(studentRepositoryProvider).list(query: _query, academicYearId: yearId, status: _status);
    }
    return _future!;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final academic = ref.watch(academicControllerProvider);
    final mediaDir = ref.watch(startupStateProvider).mediaDir;
    final can = ref.watch(permissionCheckerProvider);
    final future = _load(academic.activeYear?.id, ref.watch(studentsRevisionProvider));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final List<Division> divisionsOfProgram = _programId == null ? const [] : academic.divisionsOf(_programId!);

    return SdPage(
      children: [
        Row(
          children: [
            Expanded(child: Text(l10n.studentsTitle, style: theme.textTheme.headlineSmall)),
            if (can(Permissions.studentsEdit))
              SdButton(
                label: l10n.actionAddStudent,
                icon: Icons.person_add_alt,
                onPressed: () => context.go('/students/new'),
              ),
            PopupMenuButton<String>(
              tooltip: l10n.studentsMore,
              onSelected: (v) {
                switch (v) {
                  case 'import':
                    context.go('/students/import');
                  case 'photos':
                    context.go('/students/import-photos');
                  case 'xlsx':
                    _export(excel: true);
                  case 'csv':
                    _export(excel: false);
                }
              },
              itemBuilder: (_) => [
                if (can(Permissions.studentsImport)) ...[
                  PopupMenuItem(value: 'import', child: Text(l10n.importStudentsTitle)),
                  PopupMenuItem(value: 'photos', child: Text(l10n.importPhotosTitle)),
                  const PopupMenuDivider(),
                ],
                PopupMenuItem(value: 'xlsx', child: Text(l10n.exportExcel)),
                PopupMenuItem(value: 'csv', child: Text(l10n.exportCsv)),
              ],
            ),
          ],
        ),
        const SizedBox(height: SdSpace.lg),
        SdTextField(
          controller: _search,
          hint: l10n.studentsSearchHint,
          prefixIcon: Icons.search,
          onChanged: _onSearch,
        ),
        const SizedBox(height: SdSpace.md),
        Wrap(
          spacing: SdSpace.sm,
          runSpacing: SdSpace.sm,
          children: [
            _FilterChipMenu<String?>(
              label: l10n.studentsFilterClass,
              valueText: academic.programs.where((p) => p.id == _programId).firstOrNull?.name ?? l10n.studentsFilterAll,
              options: [(null, l10n.studentsFilterAll), for (final p in academic.programs) (p.id, p.name)],
              onSelected: (v) => setState(() {
                _programId = v;
                _divisionId = null;
              }),
            ),
            if (_programId != null)
              _FilterChipMenu<String?>(
                label: l10n.studentsFilterDivision,
                valueText:
                    academic.divisions.where((d) => d.id == _divisionId).firstOrNull?.name ?? l10n.studentsFilterAll,
                options: [(null, l10n.studentsFilterAll), for (final d in divisionsOfProgram) (d.id, d.name)],
                onSelected: (v) => setState(() => _divisionId = v),
              ),
            _FilterChipMenu<StudentStatus?>(
              label: l10n.studentsFilterStatus,
              valueText: _status == null ? l10n.studentsFilterAll : studentStatusLabel(l10n, _status!),
              options: [
                (null, l10n.studentsFilterAll),
                for (final s in StudentStatus.values) (s, studentStatusLabel(l10n, s)),
              ],
              onSelected: (v) => setState(() => _status = v),
            ),
            _FilterChipMenu<StudentSort>(
              label: l10n.sortBy,
              valueText: studentSortLabel(l10n, _effectiveSort),
              options: [for (final o in StudentSort.values) (o, studentSortLabel(l10n, o))],
              onSelected: (v) => setState(() => _sort = v),
            ),
          ],
        ),
        const SizedBox(height: SdSpace.lg),
        FutureBuilder<List<StudentListItem>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SdEmptyState(icon: Icons.error_outline, title: l10n.saveFailed, message: '${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return Column(children: [
                for (var i = 0; i < 6; i++)
                  const Padding(padding: EdgeInsets.only(bottom: SdSpace.md), child: SdSkeleton(height: 48)),
              ]);
            }
            var items = snapshot.data!;
            final mine = ref.watch(allowedDivisionsProvider);
            if (mine != null) items = items.where((s) => mine.contains(s.divisionId)).toList();
            if (_programId != null) {
              final allowed = _divisionId != null ? {_divisionId} : divisionsOfProgram.map((d) => d.id).toSet();
              items = items.where((s) => allowed.contains(s.divisionId)).toList();
            }
            items = sortStudents(items, _effectiveSort);
            _shown = items;
            if (items.isEmpty) {
              final nothingSaved = _query.isEmpty && _programId == null;
              return SdEmptyState(
                icon: Icons.person_search_outlined,
                title: nothingSaved ? l10n.studentsEmptyTitle : l10n.studentsNoMatch,
                message: nothingSaved ? l10n.studentsEmptyMessage : l10n.studentsNoMatchHint,
                action: nothingSaved
                    ? SdButton(
                        label: l10n.actionImportExcel,
                        icon: Icons.upload_file_outlined,
                        onPressed: () => context.go('/students/import'),
                      )
                    : null,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_selecting)
                  Row(children: [
                    Expanded(child: Text(l10n.studentsCount(items.length), style: theme.textTheme.bodySmall)),
                    SdButton(
                      label: l10n.batchSelect,
                      icon: Icons.checklist,
                      variant: SdButtonVariant.text,
                      onPressed: () => setState(() => _selecting = true),
                    ),
                  ])
                else
                  SdCard(
                    child: Wrap(
                      spacing: SdSpace.sm,
                      runSpacing: SdSpace.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(l10n.batchSelected(_selected.length), style: theme.textTheme.titleSmall),
                        SdButton(
                          label: _selected.length == items.length ? l10n.batchSelectNone : l10n.batchSelectAll(items.length),
                          variant: SdButtonVariant.text,
                          onPressed: () => setState(() {
                            if (_selected.length == items.length) {
                              _selected.clear();
                            } else {
                              _selected
                                ..clear()
                                ..addAll(items.map((i) => i.id));
                            }
                          }),
                        ),
                        SdButton(
                          label: l10n.batchLeft,
                          icon: Icons.logout,
                          variant: SdButtonVariant.secondary,
                          onPressed: _working || _selected.isEmpty ? null : () => _batch('left'),
                        ),
                        SdButton(
                          label: l10n.batchBin,
                          icon: Icons.delete_outline,
                          variant: SdButtonVariant.secondary,
                          onPressed: _working || _selected.isEmpty ? null : () => _batch('bin'),
                        ),
                        SdButton(label: l10n.cancel, variant: SdButtonVariant.text, onPressed: _endSelection),
                      ],
                    ),
                  ),
                const SizedBox(height: SdSpace.sm),
                SdCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (wide) const _TableHeader(),
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0 || wide) const Divider(height: 1),
                        _StudentRow(
                          item: items[i],
                          wide: wide,
                          selecting: _selecting,
                          selected: _selected.contains(items[i].id),
                          onToggle: () => setState(() {
                            if (!_selected.remove(items[i].id)) _selected.add(items[i].id);
                          }),
                          placement: placementName(academic, items[i].divisionId),
                          photo: studentPhoto(mediaDir, items[i].photoFileName),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FilterChipMenu<T> extends StatelessWidget {
  const _FilterChipMenu({required this.label, required this.valueText, required this.options, required this.onSelected});

  final String label;
  final String valueText;
  final List<(T, String)> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.filter_list, size: 18),
      label: Text('$label: $valueText'),
      onPressed: () async {
        final picked = await SdSheet.show<(T,)>(
          context,
          title: label,
          builder: (sheet) => ListView(
            shrinkWrap: true,
            children: [
              for (final o in options) ListTile(title: Text(o.$2), onTap: () => Navigator.of(sheet).pop((o.$1,))),
            ],
          ),
        );
        if (picked != null) onSelected(picked.$1);
      },
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: SdColors.of(context).textMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.lg, vertical: SdSpace.md),
      child: Row(
        children: [
          const SizedBox(width: 48),
          Expanded(flex: 4, child: Text(l10n.fieldName, style: style)),
          Expanded(flex: 2, child: Text(l10n.idGr, style: style)),
          Expanded(flex: 2, child: Text(l10n.studentCode, style: style)),
          Expanded(flex: 3, child: Text(l10n.sectionPlacement, style: style)),
          Expanded(flex: 2, child: Text(l10n.fieldMobile, style: style)),
          Expanded(flex: 2, child: Text(l10n.studentsFilterStatus, style: style)),
        ],
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.item,
    required this.wide,
    required this.placement,
    required this.photo,
    this.selecting = false,
    this.selected = false,
    this.onToggle,
  });

  final StudentListItem item;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggle;
  final bool wide;
  final String? placement;
  final File? photo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final where = placement == null
        ? l10n.studentsNotPlaced
        : (item.rollNumber == null ? placement! : '$placement · ${l10n.rollShort(item.rollNumber!)}');
    final statusColor = item.status == StudentStatus.active ? sd.present : sd.textMuted;

    void open() => selecting ? onToggle?.call() : context.go('/students/${item.id}');
    final gr = (item.grNumber ?? '').isEmpty ? '' : '${l10n.idGr} ${item.grNumber} · ';
    final Widget avatar = selecting
        ? Checkbox(value: selected, onChanged: (_) => onToggle?.call())
        : StudentAvatar(name: item.fullName, photo: photo);

    if (!wide) {
      return ListTile(
        leading: avatar,
        selected: selected,
        title: Text(item.fullName),
        subtitle: Text('$gr${item.displayCode} · $where'),
        trailing: item.status == StudentStatus.active
            ? const Icon(Icons.chevron_right)
            : StatusPill(text: studentStatusLabel(l10n, item.status), color: statusColor),
        onTap: open,
      );
    }
    return InkWell(
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SdSpace.lg, vertical: SdSpace.sm),
        child: Row(
          children: [
            selecting
                ? SizedBox(width: 36, child: Checkbox(value: selected, onChanged: (_) => onToggle?.call()))
                : StudentAvatar(name: item.fullName, photo: photo, size: 36),
            const SizedBox(width: SdSpace.md),
            Expanded(flex: 4, child: Text(item.fullName, style: theme.textTheme.bodyMedium)),
            Expanded(flex: 2, child: Text(item.grNumber ?? '—', style: theme.textTheme.bodySmall)),
            Expanded(flex: 2, child: Text(item.displayCode, style: theme.textTheme.bodySmall)),
            Expanded(flex: 3, child: Text(where, style: theme.textTheme.bodySmall)),
            Expanded(flex: 2, child: Text(item.primaryMobile ?? '—', style: theme.textTheme.bodySmall)),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(text: studentStatusLabel(l10n, item.status), color: statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
