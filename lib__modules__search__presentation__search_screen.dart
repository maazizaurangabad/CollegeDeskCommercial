import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/modules/module_providers.dart';
import '../../students/application/students_providers.dart';
import '../../students/domain/student_models.dart';
import '../../students/presentation/student_labels.dart';

/// One search box for the whole app: students (by name, code, GR, PEN,
/// APAAR, Saral, admission number or a guardian's mobile), classes and
/// Settings pages.
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

  @override
  void initState() {
    super.initState();
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
      final q = value.trim();
      setState(() {
        _query = q;
        _students = q.length < 2
            ? null
            : ref.read(studentRepositoryProvider).list(
                  query: q,
                  academicYearId: ref.read(academicControllerProvider).activeYear?.id,
                  limit: 30,
                );
      });
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
        const SizedBox(height: SdSpace.xl),
        if (q.isEmpty) ...[
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
          if (_students != null)
            FutureBuilder<List<StudentListItem>>(
              future: _students,
              builder: (context, snapshot) {
                final items = snapshot.data;
                if (items == null) return const SdSkeleton(height: 64);
                if (items.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: SdSpace.xl),
                  child: SdSection(
                    title: l10n.searchStudents(items.length),
                    child: SdCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (final s in items)
                          ListTile(
                            leading: StudentAvatar(name: s.fullName, photo: studentPhoto(mediaDir, s.photoFileName)),
                            title: Text(s.fullName),
                            subtitle: Text([
                              s.displayCode,
                              placementName(academic, s.divisionId) ?? '',
                              if (s.rollNumber != null) l10n.rollShort(s.rollNumber!),
                              s.primaryMobile ?? '',
                            ].where((x) => x.isNotEmpty).join(' · ')),
                            trailing: s.status == StudentStatus.active
                                ? const Icon(Icons.chevron_right)
                                : StatusPill(text: studentStatusLabel(l10n, s.status), color: SdColors.of(context).textMuted),
                            onTap: () => _go('/students/${s.id}'),
                          ),
                      ]),
                    ),
                  ),
                );
              },
            ),
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
