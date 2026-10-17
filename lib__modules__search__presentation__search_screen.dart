import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../platform/staff/staff_providers.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/academic/academic_models.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/modules/module_providers.dart';
import '../../students/application/students_providers.dart';
import '../../students/domain/student_models.dart';
import '../../students/presentation/student_labels.dart';
import '../application/student_search.dart';

/// One search box for the whole app: students (by name, code, G.R., roll
/// number, PEN, APAAR, Saral, admission number, a parent's name or mobile,
/// or the institution's own fields such as FYJC Application ID), classes
/// and Settings pages. Students can be narrowed by year, class and status.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _recentKey = 'search.recent';

  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<List<StudentListItem>>? _students;
  List<String> _recent = const [];

  // Filters for students.
  String? _yearId;
  String? _programId;
  String? _divisionId;
  StudentStatus? _status = StudentStatus.active;
  int _shown = _page;
  static const _page = 60;

  @override
  void initState() {
    super.initState();
    // Once after an update, so own fields (FYJC ID...) can be searched.
    ref
        .read(studentRepositoryProvider)
        .ensureSearchIndex(ref.read(appSettingsRepositoryProvider))
        .then((changed) {
          if (changed && mounted) _run();
        })
        .catchError((Object _) {});
    ref.read(appSettingsRepositoryProvider).getValue(_recentKey).then((raw) {
      if (raw == null || !mounted) return;
      setState(() => _recent = (jsonDecode(raw) as List<dynamic>).map((e) => '$e').toList());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _query = value.trim();
      _run();
    });
  }

  /// The chosen classes: one division, all divisions of a class, or none.
  Set<String>? _divisionIds() {
    final academic = ref.read(academicControllerProvider);
    if (_yearId != null && _yearId != academic.activeYear?.id) return null;
    if (_divisionId != null) return {_divisionId!};
    if (_programId != null) return academic.divisionsOf(_programId!).map((d) => d.id).toSet();
    return null;
  }

  void _run() {
    final q = _query;
    var classes = _divisionIds();
    // A teacher finds only students of their own classes.
    final mine = ref.read(allowedDivisionsProvider);
    if (mine != null) classes = classes == null ? mine : classes.intersection(mine);
    final searchable = q.length >= 2 || rollQuery(q) != null || (q.isEmpty && classes != null);
    setState(() {
      _shown = _page;
      _students = searchable
          ? searchStudents(
              ref.read(studentRepositoryProvider),
              query: q,
              academicYearId: _yearId ?? ref.read(academicControllerProvider).activeYear?.id,
              divisionIds: classes,
              status: _status,
            )
          : null;
    });
  }

  Future<void> _remember() async {
    final q = _query.trim();
    if (q.length < 2) return;
    final next = [q, ..._recent.where((r) => r.toLowerCase() != q.toLowerCase())].take(8).toList();
    _recent = next;
    await ref.read(appSettingsRepositoryProvider).setValue(_recentKey, jsonEncode(next));
  }

  void _go(String route) {
    _remember();
    context.go(route);
  }

  /// Pages that search can open: (title, route, icon, extra words people may type).
  List<(String, String, IconData, String)> _settingsPages(AppLocalizations l10n) {
    final attendance = ref.read(enabledModulesProvider).contains('attendance');
    return [
      (l10n.settingsInstitutionProfile, '/settings/institution', Icons.apartment_outlined,
          'college school name logo colour color address udise board medium'),
      (l10n.settingsAcademicYears, '/settings/academic-years', Icons.calendar_month_outlined, 'year session active close'),
      (l10n.settingsClassesDivisions, '/settings/classes', Icons.account_tree_outlined,
          'class division standard std section batch course'),
      (l10n.settingsStudentFields, '/settings/student-fields', Icons.tune_outlined, 'extra field category caste custom'),
      if (attendance)
        (l10n.settingsAttendance, '/settings/attendance', Icons.fact_check_outlined,
            'holiday holidays calendar exam day weekly off sunday saturday mark marks code codes leave medical edit window सुट्टी'),
      (l10n.settingsImports, '/settings/imports', Icons.history_outlined, 'import history undo excel'),
      (l10n.promoTitle, '/students/promotion', Icons.upgrade,
          'promotion promote next year class year end new session pass fail atkt repeat detained 12th left'),
      (l10n.settingsRecycleBin, '/settings/recycle-bin', Icons.delete_outline, 'deleted restore bin trash'),
      (l10n.settingsModules, '/settings/modules', Icons.extension_outlined, 'module modules switch on off'),
      (l10n.settingsBackup, '/settings/backup', Icons.backup_outlined, 'backup restore password drive automatic'),
      (l10n.settingsSecurity, '/settings/security', Icons.lock_outline, 'pin lock fingerprint face password recovery'),
      (l10n.settingsDataHealth, '/settings/data-health', Icons.health_and_safety_outlined, 'check problems errors duplicate'),
      (l10n.importStudentsTitle, '/students/import', Icons.upload_file_outlined, 'excel csv import upload sheet'),
      (l10n.importPhotosTitle, '/students/import-photos', Icons.photo_library_outlined, 'photo photos picture zip'),
      if (attendance)
        (l10n.attendanceRegister, '/attendance/register', Icons.calendar_view_month_outlined,
            'register monthly month percentage defaulter below 75'),
      if (attendance) (l10n.attendanceTitle, '/attendance', Icons.fact_check_outlined, 'attendance mark absent present today'),
      if (ref.read(enabledModulesProvider).contains('results')) ...[
        (l10n.navResults, '/results', Icons.emoji_events_outlined, 'result results marks exam term sheet pass fail percentage rank'),
        (l10n.resSetup, '/results/setup', Icons.tune_outlined, 'subject subjects exam exams term atkt distinction grade passing marks'),
      ],
      if (ref.read(enabledModulesProvider).contains('fees')) ...[
        (l10n.feeTakePayment, '/fees/pay', Icons.currency_rupee, 'fee fees pay payment collect receipt cash upi cheque'),
        (l10n.navFees, '/fees', Icons.receipt_long_outlined, 'fee fees receipt register collection today'),
        (l10n.feeSetup, '/fees/setup', Icons.tune_outlined,
            'fee fees structure head heads tuition admission category concession freeship amount installment due date'),
        if (ref.read(enabledModulesProvider).contains('messages'))
          (l10n.feeReminders, '/fees/reminders', Icons.forum_outlined, 'fee fees reminder reminders pending due whatsapp parent'),
        if (ref.read(enabledModulesProvider).contains('reports')) ...[
          (l10n.feeReportDayBook, '/reports/feeDayBook', Icons.menu_book_outlined, 'fee day book collection report cash upi excel pdf'),
          (l10n.feeReportDefaulters, '/reports/feeDefaulters', Icons.money_off_outlined, 'fee defaulters pending balance overdue report'),
          (l10n.feeReportClassSummary, '/reports/feeClassSummary', Icons.account_balance_wallet_outlined, 'fee class balance summary report'),
          (l10n.feeReportHeads, '/reports/feeHeads', Icons.pie_chart_outline, 'fee head wise collection report'),
        ],
      ],
      if (ref.read(enabledModulesProvider).contains('messages')) ...[
        (l10n.navMessages, '/messages', Icons.forum_outlined,
            'message messages parent parents whatsapp sms absent absentee summary send notify inform'),
        (l10n.msgTabHistory, '/messages?tab=history', Icons.history, 'message history sent whatsapp log parent'),
        (l10n.settingsMessages, '/messages/templates', Icons.edit_note_outlined,
            'message template templates text wording parent whatsapp leave'),
      ],
      if (ref.read(enabledModulesProvider).contains('certificates')) ...[
        (l10n.certIssue, '/certificates/new', Icons.workspace_premium_outlined,
            'certificate bonafide lc leaving nirgam utara register extract tc transfer noc no dues character caste verification validation form 15a issue'),
        (l10n.certRegister, '/certificates', Icons.list_alt, 'certificate register issued reprint cancel serial outward count'),
        (l10n.certRegisterReport, '/reports/certificates', Icons.table_chart_outlined, 'certificate register report excel outward inward export'),
      ],
      if (ref.read(enabledModulesProvider).contains('reports')) ...[
        (l10n.reportRegisterTitle, '/reports/register', Icons.picture_as_pdf_outlined, 'report pdf print register monthly'),
        (l10n.reportDefaultersName, '/reports/defaulters', Icons.trending_down, 'report defaulter defaulters below 75 low pdf'),
        (l10n.reportAbsenteesTitle, '/reports/absentees', Icons.person_off_outlined, 'report absent absentee today pdf'),
        (l10n.reportSummaryTitle, '/reports/summary', Icons.insights_outlined, 'report summary average pdf'),
        (l10n.reportClassListTitle, '/reports/classList', Icons.format_list_numbered, 'report class list roll pdf print'),
        (l10n.reportMasterTitle, '/reports/master', Icons.groups_outlined, 'report student master list all pdf'),
      ],
    ];
  }

  Widget _filters(AppLocalizations l10n, AcademicSnapshot academic) {
    final activeId = academic.activeYear?.id;
    final yearId = _yearId ?? activeId;
    final current = yearId == activeId;
    Widget box(Widget child) => SizedBox(width: 200, child: child);
    return Wrap(
      spacing: SdSpace.sm,
      runSpacing: SdSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (academic.years.length > 1)
          box(SdSelectField<String>(
            label: l10n.academicYearShort,
            value: yearId,
            options: [for (final y in academic.years) (y.id, y.label)],
            onChanged: (v) {
              _yearId = v;
              _programId = null;
              _divisionId = null;
              _run();
            },
          )),
        if (current) ...[
          box(SdSelectField<String>(
            label: l10n.studentsFilterClass,
            value: _programId,
            options: [for (final p in academic.programs) (p.id, p.name)],
            clearLabel: l10n.studentsFilterAll,
            onChanged: (v) {
              _programId = v;
              _divisionId = null;
              _run();
            },
          )),
          if (_programId != null)
            box(SdSelectField<String>(
              label: l10n.studentsFilterDivision,
              value: _divisionId,
              options: [for (final d in academic.divisionsOf(_programId!)) (d.id, d.name)],
              clearLabel: l10n.studentsFilterAll,
              onChanged: (v) {
                _divisionId = v;
                _run();
              },
            )),
        ],
        for (final (value, label) in [
          (StudentStatus.active, studentStatusLabel(l10n, StudentStatus.active)),
          (StudentStatus.left, studentStatusLabel(l10n, StudentStatus.left)),
          (null, l10n.studentsFilterAll),
        ])
          ChoiceChip(
            label: Text(label),
            selected: _status == value,
            showCheckmark: false,
            onSelected: (_) {
              _status = value;
              _run();
            },
          ),
      ],
    );
  }

  Widget _studentResults(AppLocalizations l10n, AcademicSnapshot academic, Directory? mediaDir) {
    final theme = Theme.of(context);
    return FutureBuilder<List<StudentListItem>>(
      future: _students,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: SdSpace.xl),
            child: SdEmptyState(icon: Icons.error_outline, title: l10n.searchFailed, message: l10n.searchFailedHint),
          );
        }
        final items = snapshot.data;
        if (items == null) return const SdSkeleton(height: 96);
        if (items.isEmpty) return const SizedBox.shrink();
        final shown = items.take(_shown).toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: SdSpace.xl),
          child: SdSection(
            title: l10n.searchStudents(items.length),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 960 ? 3 : (constraints.maxWidth >= 620 ? 2 : 1);
                  final width = (constraints.maxWidth - SdSpace.md * (columns - 1)) / columns;
                  return Wrap(
                    spacing: SdSpace.md,
                    runSpacing: SdSpace.md,
                    children: [
                      for (final s in shown)
                        SizedBox(
                          width: width,
                          child: _StudentCard(
                            student: s,
                            classLabel: placementName(academic, s.divisionId),
                            photo: studentPhoto(mediaDir, s.photoFileName),
                            onTap: () => _go('/students/${s.id}'),
                          ),
                        ),
                    ],
                  );
                }),
                if (items.length > shown.length) ...[
                  const SizedBox(height: SdSpace.md),
                  Align(
                    child: SdButton(
                      label: l10n.searchShowMore(items.length - shown.length),
                      variant: SdButtonVariant.secondary,
                      onPressed: () => setState(() => _shown += _page),
                    ),
                  ),
                ],
                if (_query.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: SdSpace.sm),
                    child: Text(l10n.searchClassListed, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final academic = ref.watch(academicControllerProvider);
    final mediaDir = ref.watch(startupStateProvider).mediaDir;
    final attendanceOn = ref.watch(enabledModulesProvider).contains('attendance');
    final q = _query.toLowerCase();

    final divisions = q.isEmpty
        ? const <(String, String)>[]
        : [
            for (final d in academic.divisions)
              if ((placementName(academic, d.id) ?? '').toLowerCase().contains(q)) (d.id, placementName(academic, d.id)!),
          ];
    // A page matches its title or any of its extra words, e.g. "holiday" finds Attendance settings.
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final pages = q.isEmpty
        ? const <(String, String, IconData, String)>[]
        : _settingsPages(l10n).where((p) {
            final text = '${p.$1} ${p.$4}'.toLowerCase();
            return words.every(text.contains);
          }).toList();

    return SdPage(
      children: [
        Row(
          children: [
            IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
            const SizedBox(width: SdSpace.xs),
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _changed,
                onSubmitted: (_) => _remember(),
                decoration: InputDecoration(
                  hintText: l10n.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _controller.clear();
                            _changed('');
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: SdSpace.md),
        _filters(l10n, academic),
        const SizedBox(height: SdSpace.xl),
        if (q.isEmpty && _students == null) ...[
          if (_recent.isNotEmpty)
            SdSection(
              title: l10n.searchRecent,
              child: Wrap(
                spacing: SdSpace.sm,
                runSpacing: SdSpace.sm,
                children: [
                  for (final r in _recent)
                    ActionChip(
                      avatar: const Icon(Icons.history, size: 18),
                      label: Text(r),
                      onPressed: () {
                        _controller.text = r;
                        _changed(r);
                      },
                    ),
                ],
              ),
            )
          else
            Text(l10n.searchExplain, style: theme.textTheme.bodyMedium),
        ] else ...[
          if (_students != null) _studentResults(l10n, academic, mediaDir),
          if (divisions.isNotEmpty) ...[
            SdSection(
              title: l10n.searchClasses,
              child: SdCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (id, name) in divisions)
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(name),
                      subtitle: attendanceOn ? Text(l10n.actionMarkAttendance) : null,
                      onTap: () => _go(attendanceOn ? '/attendance?division=$id' : '/settings/classes'),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: SdSpace.xl),
          ],
          if (pages.isNotEmpty) ...[
            SdSection(
              title: l10n.searchPages,
              child: SdCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (label, route, icon, _) in pages)
                    ListTile(leading: Icon(icon), title: Text(label), onTap: () => _go(route)),
                ]),
              ),
            ),
            const SizedBox(height: SdSpace.xl),
          ],
          FutureBuilder<List<StudentListItem>>(
            future: _students ?? Future.value(const <StudentListItem>[]),
            builder: (context, snapshot) {
              final none = snapshot.hasData && snapshot.data!.isEmpty && divisions.isEmpty && pages.isEmpty;
              return none
                  ? SdEmptyState(icon: Icons.search_off, title: l10n.searchNothing, message: l10n.searchNothingHint)
                  : const SizedBox.shrink();
            },
          ),
        ],
      ],
    );
  }
}

/// One student in the search results: photo, name, class and roll, G.R.
/// and code, and a status chip when the student is not active.
class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student, required this.classLabel, required this.photo, required this.onTap});

  final StudentListItem student;
  final String? classLabel;
  final File? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final s = student;
    final line1 = [
      if ((classLabel ?? '').isNotEmpty) classLabel!,
      if (s.rollNumber != null) l10n.rollShort(s.rollNumber!),
    ].join(' · ');
    final line2 = [
      if ((s.grNumber ?? '').isNotEmpty) '${l10n.idGr} ${s.grNumber}',
      s.displayCode,
    ].join(' · ');
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SdRadius.md),
        side: BorderSide(color: sd.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(SdSpace.md),
          child: Row(
            children: [
              StudentAvatar(name: s.fullName, photo: photo, size: 52),
              const SizedBox(width: SdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (line1.isNotEmpty)
                      Text(line1, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                    Text(line2, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
                  ],
                ),
              ),
              if (s.status != StudentStatus.active)
                StatusPill(text: studentStatusLabel(l10n, s.status), color: sd.textMuted)
              else
                Icon(Icons.chevron_right, color: sd.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
