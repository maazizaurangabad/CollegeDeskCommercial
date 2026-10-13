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

  List<(String, String, IconData)> _settingsPages(AppLocalizations l10n) {
    final attendance = ref.read(enabledModulesProvider).contains('attendance');
    return [
      (l10n.settingsInstitutionProfile, '/settings/institution', Icons.apartment_outlined),
      (l10n.settingsAcademicYears, '/settings/academic-years', Icons.calendar_month_outlined),
      (l10n.settingsClassesDivisions, '/settings/classes', Icons.account_tree_outlined),
      (l10n.settingsStudentFields, '/settings/student-fields', Icons.tune_outlined),
      if (attendance) (l10n.settingsAttendance, '/settings/attendance', Icons.fact_check_outlined),
      (l10n.settingsImports, '/settings/imports', Icons.history_outlined),
      (l10n.settingsRecycleBin, '/settings/recycle-bin', Icons.delete_outline),
      (l10n.settingsModules, '/settings/modules', Icons.extension_outlined),
      (l10n.settingsBackup, '/settings/backup', Icons.backup_outlined),
      (l10n.settingsSecurity, '/settings/security', Icons.lock_outline),
      (l10n.settingsDataHealth, '/settings/data-health', Icons.health_and_safety_outlined),
      (l10n.importStudentsTitle, '/students/import', Icons.upload_file_outlined),
      (l10n.importPhotosTitle, '/students/import-photos', Icons.photo_library_outlined),
      if (attendance) (l10n.attendanceRegister, '/attendance/register', Icons.calendar_view_month_outlined),
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
    final pages = q.isEmpty ? const <(String, String, IconData)>[] : _settingsPages(l10n).where((p) => p.$1.toLowerCase().contains(q)).toList();

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
                  for (final (label, route, icon) in pages)
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
