import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../platform/staff/staff_models.dart';
import '../../../app/startup/app_bootstrap.dart';
import '../../../core/backup/backup_password_store.dart';
import '../../../core/security/secret_store.dart';
import '../../../design_system/components/components.dart';
import '../../../platform/data/data_providers.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/demo/demo_data.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../students/application/students_providers.dart';
import 'dashboard_lists.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final can = ref.watch(permissionCheckerProvider);
    final org = ref.watch(activeOrganizationProvider);
    final isDemo = ref.watch(isDemoModeProvider);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    const snap = DemoData.snapshot;
    final studentCount = ref.watch(activeStudentCountProvider).valueOrNull;
    final today = ref.watch(todayAttendanceProvider).valueOrNull;
    final hasToday = !isDemo && today != null && today.marked > 0;
    final todayPresent = today?.present ?? 0;
    final todayAbsent = today?.absent ?? 0;
    final todayCounted = todayPresent + todayAbsent;

    return SdPage(
      children: [
        // Institution header: the institution's name sits on its brand rule.
        Container(
          padding: const EdgeInsets.only(left: SdSpace.lg),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(org.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: SdSpace.xs),
              Text(
                '${l10n.academicYear(org.activeAcademicYear)}\n${DateFormat('EEEE, d MMMM y').format(DateTime.now())}',
                style: theme.textTheme.bodyMedium?.copyWith(color: sd.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: SdSpace.xxl),
        SdSection(
          title: l10n.dashboardToday,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 560 ? 2 : 4;
                  final tileWidth = (constraints.maxWidth - SdSpace.md * (columns - 1)) / columns;
                  // Real institutions show dashes until students and attendance exist.
                  String show(String value) => isDemo ? value : '—';
                  final tiles = [
                    SdStatTile(label: l10n.statTotalStudents, value: studentCount == null ? '—' : '$studentCount'),
                    SdStatTile(
                      label: l10n.statPresent,
                      value: hasToday ? '$todayPresent' : show('${snap.present}'),
                      accent: sd.present,
                    ),
                    SdStatTile(
                      label: l10n.statAbsent,
                      value: hasToday ? '$todayAbsent' : show('${snap.absent}'),
                      accent: sd.absent,
                    ),
                    SdStatTile(
                      label: l10n.statAttendance,
                      value: hasToday
                          ? '${(todayPresent * 100 / (todayCounted == 0 ? 1 : todayCounted)).toStringAsFixed(1)}%'
                          : show('${snap.attendancePercent.toStringAsFixed(1)}%'),
                    ),
                  ];
                  return Wrap(
                    spacing: SdSpace.md,
                    runSpacing: SdSpace.md,
                    children: [for (final t in tiles) SizedBox(width: tileWidth, child: t)],
                  );
                },
              ),
              const SizedBox(height: SdSpace.sm),
              Text(isDemo ? l10n.demoFiguresNote : l10n.liveFiguresNote, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: SdSpace.xxl),
        const DashboardTodayLists(),
        SdSection(
          title: l10n.quickActions,
          child: Wrap(
            spacing: SdSpace.sm,
            runSpacing: SdSpace.sm,
            children: [
              if (can(Permissions.attendanceMark))
              SdButton(
                label: l10n.actionMarkAttendance,
                icon: Icons.fact_check_outlined,
                onPressed: () => context.go('/attendance'),
              ),
              SdButton(
                label: l10n.actionSearchStudent,
                icon: Icons.search,
                variant: SdButtonVariant.secondary,
                onPressed: () => context.go('/search'),
              ),
              if (can(Permissions.studentsEdit))
              SdButton(
                label: l10n.actionAddStudent,
                icon: Icons.person_add_alt,
                variant: SdButtonVariant.secondary,
                onPressed: () => context.go('/students/new'),
              ),
              if (can(Permissions.certificatesIssue))
              SdButton(
                label: l10n.certIssue,
                icon: Icons.workspace_premium_outlined,
                variant: SdButtonVariant.secondary,
                onPressed: () => context.go('/certificates/new'),
              ),
              if (can(Permissions.studentsImport))
              SdButton(
                label: l10n.actionImportExcel,
                icon: Icons.upload_file_outlined,
                variant: SdButtonVariant.secondary,
                onPressed: () => context.go('/students/import'),
              ),
            ],
          ),
        ),
        const SizedBox(height: SdSpace.xxl),
        SdSection(
          title: l10n.attentionRequired,
          child: FutureBuilder<List<String>>(
            future: isDemo ? Future.value(const <String>[]) : _backupReminders(ref, l10n),
            builder: (context, snapshot) {
              final reminders = snapshot.data ?? const <String>[];
              if (reminders.isEmpty) {
                return SdCard(
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: sd.present),
                      const SizedBox(width: SdSpace.md),
                      Expanded(child: Text(l10n.attentionNone, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                );
              }
              return SdCard(
                onTap: () => context.go('/settings/backup'),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_outlined, color: sd.leave),
                    const SizedBox(width: SdSpace.md),
                    Expanded(child: Text(reminders.join('\n'), style: theme.textTheme.bodyMedium)),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: SdSpace.xxl),
        const DashboardRecentActivity(),
      ],
    );
  }

  /// Backup reminders for a real institution: no password, or nothing
  /// saved away from the device in the last 7 days.
  Future<List<String>> _backupReminders(WidgetRef ref, AppLocalizations l10n) async {
    final out = <String>[];
    if (await BackupPasswordStore(const DeviceSecretStore()).read() == null) out.add(l10n.reminderPassword);
    final raw = await ref.read(appSettingsRepositoryProvider).getValue(AppBootstrap.lastSavedKey);
    final last = raw == null ? null : DateTime.tryParse(raw);
    if (last == null || DateTime.now().difference(last).inDays >= 7) out.add(l10n.reminderBackup);
    return out;
  }
}
