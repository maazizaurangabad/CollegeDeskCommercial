import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/activity_repository.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/modules/module_providers.dart';
import '../../attendance/presentation/attendance_labels.dart';
import '../../students/presentation/student_labels.dart';
import '../application/dashboard_providers.dart';

/// Today's working lists: divisions not marked, absentees, low attendance, birthdays.
/// Each list hides itself when empty, so a quiet day shows a short dashboard.
class DashboardTodayLists extends ConsumerWidget {
  const DashboardTodayLists({super.key});

  static const _shown = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final academic = ref.watch(academicControllerProvider);
    final mediaDir = ref.watch(startupStateProvider).mediaDir;
    final attendanceOn = ref.watch(enabledModulesProvider).contains('attendance');
    String place(String divisionId) => placementName(academic, divisionId) ?? '';

    final sections = <Widget>[];

    void add(String title, Widget child, {Widget? trailing}) {
      sections
        ..add(SdSection(title: title, trailing: trailing, child: child))
        ..add(const SizedBox(height: SdSpace.xxl));
    }

    Widget more(int total) => total > _shown
        ? Padding(
            padding: const EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, SdSpace.md),
            child: Text(l10n.dashboardAndMore(total - _shown), style: theme.textTheme.bodySmall),
          )
        : const SizedBox.shrink();

    if (attendanceOn) {
      final unmarked = ref.watch(unmarkedTodayProvider).valueOrNull ?? const <String>[];
      if (unmarked.isNotEmpty) {
        add(
          l10n.dashboardUnmarked(unmarked.length),
          Wrap(
            spacing: SdSpace.sm,
            runSpacing: SdSpace.sm,
            children: [
              for (final id in unmarked)
                ActionChip(
                  avatar: Icon(Icons.fact_check_outlined, size: 18, color: sd.leave),
                  label: Text(place(id)),
                  onPressed: () => context.go('/attendance?division=$id'),
                ),
            ],
          ),
        );
      }

      final absent = ref.watch(absentTodayProvider).valueOrNull ?? const <AbsentToday>[];
      if (absent.isNotEmpty) {
        add(
          l10n.dashboardAbsentToday(absent.length),
          SdCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final a in absent.take(_shown))
                ListTile(
                  dense: true,
                  leading: StudentAvatar(name: a.student.fullName, photo: studentPhoto(mediaDir, a.student.photoFileName), size: 32),
                  title: Text(a.student.fullName),
                  subtitle: Text(place(a.divisionId)),
                  trailing: StatusPill(text: a.code, color: sd.absent),
                  onTap: () => context.go('/students/${a.student.id}'),
                ),
              more(absent.length),
            ]),
          ),
        );
      }

      final low = ref.watch(lowAttendanceProvider).valueOrNull ?? const <LowAttendance>[];
      if (low.isNotEmpty) {
        add(
          l10n.dashboardLowAttendance(low.length),
          SdCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final s in low.take(_shown))
                ListTile(
                  dense: true,
                  leading: StudentAvatar(name: s.student.fullName, photo: studentPhoto(mediaDir, s.student.photoFileName), size: 32),
                  title: Text(s.student.fullName),
                  subtitle: Text(s.student.displayCode),
                  trailing: Text(
                    '${formatPercent(s.summary.percent)}%',
                    style: theme.textTheme.titleSmall?.copyWith(color: sd.absent),
                  ),
                  onTap: () => context.go('/students/${s.student.id}'),
                ),
              more(low.length),
            ]),
          ),
          trailing: SdButton(
            label: l10n.attendanceRegister,
            variant: SdButtonVariant.text,
            onPressed: () => context.go('/attendance/register'),
          ),
        );
      }
    }

    final birthdays = ref.watch(birthdaysTodayProvider).valueOrNull ?? const [];
    if (birthdays.isNotEmpty) {
      add(
        l10n.dashboardBirthdays(birthdays.length),
        Wrap(
          spacing: SdSpace.sm,
          runSpacing: SdSpace.sm,
          children: [
            for (final b in birthdays)
              ActionChip(
                avatar: const Icon(Icons.cake_outlined, size: 18),
                label: Text(b.fullName),
                onPressed: () => context.go('/students/${b.id}'),
              ),
          ],
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections);
  }
}

/// The last few meaningful events from the audit log.
class DashboardRecentActivity extends ConsumerWidget {
  const DashboardRecentActivity({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final academic = ref.watch(academicControllerProvider);
    final items = ref.watch(recentActivityProvider).valueOrNull ?? const <ActivityItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    final when = DateFormat('d MMM, h:mm a');

    String describe(ActivityItem a) {
      switch (a.entity) {
        case 'students':
          final name = [a.value('first_name'), a.value('last_name')].whereType<String>().join(' ');
          if (a.action == 'insert') return l10n.activityStudentAdded(name.isEmpty ? '${a.value('display_code') ?? ''}' : name);
          if (a.action == 'delete') return l10n.activityStudentDeleted;
          if (a.action == 'restore') return l10n.activityStudentRestored;
          return l10n.activityStudentLeft;
        case 'attendance_sessions':
          final division = placementName(academic, a.value('division_id') as String?) ?? '';
          final date = DateTime.tryParse('${a.value('date') ?? ''}');
          final day = date == null ? '' : DateFormat('d MMM').format(date);
          return a.action == 'insert'
              ? l10n.activityAttendanceSaved(division, day)
              : l10n.activityAttendanceChanged(division, day);
        case 'import_batches':
          return a.action == 'undo' ? l10n.activityImportUndone : l10n.activityImport('${a.value('added') ?? 0}');
        case 'academic_years':
          return l10n.activityYearAdded('${a.value('label') ?? ''}');
        default:
          return a.entity;
      }
    }

    IconData icon(ActivityItem a) => switch (a.entity) {
          'students' => Icons.person_outline,
          'attendance_sessions' => Icons.fact_check_outlined,
          'import_batches' => Icons.upload_file_outlined,
          _ => Icons.history,
        };

    return SdSection(
      title: l10n.dashboardRecent,
      child: SdCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (final a in items)
            ListTile(
              dense: true,
              leading: Icon(icon(a), size: 20),
              title: Text(describe(a)),
              trailing: Text(when.format(a.at.toLocal()), style: Theme.of(context).textTheme.bodySmall),
            ),
        ]),
      ),
    );
  }
}
