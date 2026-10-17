import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/data/activity_repository.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/staff/staff_models.dart';
import '../../../platform/staff/staff_providers.dart';
import 'settings_page_header.dart';

/// What each part of the app is called in the log.
String activitySection(AppLocalizations l10n, String table) => switch (table) {
      'students' || 'student_identifiers' || 'enrollments' => l10n.logStudents,
      'student_documents' => l10n.logDocuments,
      'attendance_sessions' || 'attendance_codes' || 'calendar_days' => l10n.logAttendance,
      'certificates' => l10n.logCertificates,
      'fee_receipts' => l10n.logReceipts,
      'fee_heads' || 'fee_structures' || 'fee_due_dates' || 'student_fee_adjustments' => l10n.logFeeSetup,
      'marks' || 'exams' || 'subjects' || 'subject_choices' => l10n.logResults,
      'message_logs' => l10n.logMessages,
      'import_batches' => l10n.logImports,
      'staff_members' => l10n.logStaff,
      'academic_years' || 'programs' || 'divisions' => l10n.logClasses,
      _ => l10n.logSettings,
    };

String activityAction(AppLocalizations l10n, String action) => switch (action) {
      'insert' => l10n.logAdded,
      'update' => l10n.logChanged,
      'delete' => l10n.logRemoved,
      'restore' => l10n.logRestored,
      _ => action.isEmpty ? action : '${action[0].toUpperCase()}${action.substring(1).replaceAll('_', ' ')}',
    };

/// Settings > Activity log: every change, who made it and when.
class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  static const _everyone = '*';
  String _who = _everyone;
  late DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to = DateTime.now();
  late Future<List<ActivityItem>> _items = _load();

  Future<List<ActivityItem>> _load() => ActivityRepository(ref.read(appDatabaseProvider), ref.read(sessionProvider))
      .log(userId: _who == _everyone ? null : _who, from: _from, to: _to);

  void _reload() => setState(() => _items = _load());

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _from : _to,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    if (start) {
      _from = picked;
      if (_to.isBefore(_from)) _to = _from;
    } else {
      _to = picked;
      if (_from.isAfter(_to)) _from = _to;
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final names = ref.watch(staffNamesProvider).valueOrNull ?? const <String, String>{};
    final staff = ref.watch(staffListProvider).valueOrNull ?? const <StaffMember>[];
    final day = DateFormat('d MMM y');
    final people = [
      (_everyone, l10n.logEveryone),
      (localAdminUserId, l10n.staffAdminName),
      for (final m in staff)
        if (m.id != null) (m.id!, m.name),
    ];

    return SdPage(
      children: [
        SettingsPageHeader(title: l10n.logTitle),
        Text(l10n.logIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: SdSpace.lg),
        SdSelectField<String>(
          label: l10n.logPerson,
          value: _who,
          options: people,
          onChanged: (v) {
            _who = v ?? _everyone;
            _reload();
          },
        ),
        const SizedBox(height: SdSpace.sm),
        Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text('${l10n.reportFrom}: ${day.format(_from)}'),
            onPressed: () => _pick(true),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text('${l10n.reportTo}: ${day.format(_to)}'),
            onPressed: () => _pick(false),
          ),
        ]),
        const SizedBox(height: SdSpace.lg),
        FutureBuilder<List<ActivityItem>>(
          future: _items,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text(l10n.saveFailed);
            final items = snapshot.data;
            if (items == null) return const Center(child: CircularProgressIndicator());
            if (items.isEmpty) {
              return SdEmptyState(icon: Icons.history, title: l10n.logEmpty, message: '');
            }
            return SdCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(SdSpace.md),
                  child: Text(l10n.logCount(items.length), style: theme.textTheme.bodySmall),
                ),
                for (var i = 0; i < items.length; i++) ...[
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text('${activityAction(l10n, items[i].action)} · ${activitySection(l10n, items[i].entity)}'),
                    subtitle: Text([
                      DateFormat('d MMM y, h:mm a').format(items[i].at.toLocal()),
                      userDisplayName(names, items[i].userId, adminName: l10n.staffAdminName) ?? l10n.logUnknownPerson,
                      if (items[i].action == 'update' && items[i].details.isNotEmpty)
                        items[i].details.keys.take(4).map((k) => k.replaceAll('_', ' ')).join(', '),
                    ].join(' · ')),
                  ),
                ],
              ]),
            );
          },
        ),
      ],
    );
  }
}
