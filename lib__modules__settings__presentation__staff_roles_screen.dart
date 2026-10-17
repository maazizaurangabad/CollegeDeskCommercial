import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/staff/staff_models.dart';
import '../../../platform/staff/staff_providers.dart';

/// Section and permission names as the role editor shows them.
String permissionGroupLabel(AppLocalizations l10n, String group) => switch (group) {
      'students' => l10n.permGroupStudents,
      'attendance' => l10n.permGroupAttendance,
      'messages' => l10n.permGroupMessages,
      'fees' => l10n.permGroupFees,
      'certificates' => l10n.permGroupCertificates,
      'results' => l10n.permGroupResults,
      'reports' => l10n.permGroupReports,
      _ => l10n.permGroupSettings,
    };

String permissionLabel(AppLocalizations l10n, String p) => switch (p) {
      Permissions.studentsView => l10n.permStudentsView,
      Permissions.studentsEdit => l10n.permStudentsEdit,
      Permissions.studentsDelete => l10n.permStudentsDelete,
      Permissions.studentsSensitive => l10n.permStudentsSensitive,
      Permissions.studentsImport => l10n.permStudentsImport,
      Permissions.studentsPromote => l10n.permStudentsPromote,
      Permissions.attendanceMark => l10n.permAttendanceMark,
      Permissions.attendancePast => l10n.permAttendancePast,
      Permissions.messagesSend => l10n.permMessagesSend,
      Permissions.feesCollect => l10n.permFeesCollect,
      Permissions.feesCancel => l10n.permFeesCancel,
      Permissions.feesSetup => l10n.permFeesSetup,
      Permissions.certificatesIssue => l10n.permCertificatesIssue,
      Permissions.certificatesCancel => l10n.permCertificatesCancel,
      Permissions.resultsMarks => l10n.permResultsMarks,
      Permissions.resultsSetup => l10n.permResultsSetup,
      Permissions.reportsView => l10n.permReportsView,
      Permissions.settingsManage => l10n.permSettingsManage,
      Permissions.staffManage => l10n.permStaffManage,
      Permissions.backupManage => l10n.permBackupManage,
      _ => p,
    };

/// Settings > Staff > Roles: what each role may do.
class StaffRolesScreen extends ConsumerWidget {
  const StaffRolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final roles = ref.watch(staffRolesProvider).valueOrNull;
    final staff = ref.watch(staffListProvider).valueOrNull ?? const <StaffMember>[];

    Future<void> addRole() async {
      final name = await _askName(context, l10n);
      if (name == null || roles == null) return;
      final role = StaffRole(key: StaffRoles.keyFor(name, roles.map((r) => r.key)), label: name, permissions: const {});
      await ref.read(staffRepositoryProvider).saveRoles([...roles, role]);
      ref.read(staffRevisionProvider.notifier).state++;
      if (context.mounted) await _RoleEditor.show(context, role);
    }

    return SdPage(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: SdSpace.lg),
          child: Row(children: [
            IconButton(
              tooltip: l10n.back,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/settings/staff'),
            ),
            const SizedBox(width: SdSpace.xs),
            Expanded(child: Text(l10n.staffRoles, style: theme.textTheme.headlineSmall)),
            SdButton(label: l10n.staffRoleAdd, icon: Icons.add, onPressed: roles == null ? null : addRole),
          ]),
        ),
        Text(l10n.staffRolesIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: SdSpace.lg),
        if (roles == null)
          const Center(child: CircularProgressIndicator())
        else
          SdCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < roles.length; i++) ...[
                if (i > 0) const Divider(indent: SdSpace.lg),
                ListTile(
                  leading: Icon(roles[i].key == StaffRoles.adminKey
                      ? Icons.admin_panel_settings_outlined
                      : Icons.badge_outlined),
                  title: Text(roles[i].label),
                  subtitle: Text([
                    l10n.staffRolePermCount(roles[i].permissions.length, Permissions.all.length),
                    l10n.staffRolePeople(staff.where((s) => s.roleKey == roles[i].key).length),
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _RoleEditor.show(context, roles[i]),
                ),
              ],
            ]),
          ),
      ],
    );
  }

  static Future<String?> _askName(BuildContext context, AppLocalizations l10n) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.staffRoleAdd),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.staffRoleName, hintText: l10n.staffRoleNameHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () {
              final v = c.text.trim();
              if (v.isNotEmpty) Navigator.of(dialog).pop(v);
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

/// Tick what one role may do.
class _RoleEditor extends ConsumerStatefulWidget {
  const _RoleEditor({required this.role});

  final StaffRole role;

  static Future<void> show(BuildContext context, StaffRole role) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _RoleEditor(role: role)));

  @override
  ConsumerState<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends ConsumerState<_RoleEditor> {
  late final _label = TextEditingController(text: widget.role.label);
  late final Set<String> _perms = {...widget.role.permissions};
  bool _saving = false;

  bool get _isAdmin => widget.role.key == StaffRoles.adminKey;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final label = _label.text.trim();
    if (label.isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(staffRepositoryProvider);
      final roles = await repo.roles();
      await repo.saveRoles([
        for (final r in roles)
          if (r.key == widget.role.key)
            r.copyWith(label: label, permissions: _isAdmin ? Permissions.all : _perms)
          else
            r,
      ]);
      ref.read(staffRevisionProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      SdToast.show(context, l10n.saveFailed);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final staff = await ref.read(staffRepositoryProvider).list();
    if (!mounted) return;
    if (staff.any((s) => s.roleKey == widget.role.key)) {
      SdToast.show(context, l10n.staffRoleInUse);
      return;
    }
    final ok = await SdDialog.confirm(
      context,
      title: l10n.staffRoleDelete,
      message: l10n.staffRoleDeleteMessage(widget.role.label),
      confirmLabel: l10n.staffRoleDelete,
      cancelLabel: l10n.cancel,
    );
    if (!ok || !mounted) return;
    final repo = ref.read(staffRepositoryProvider);
    final roles = await repo.roles();
    await repo.saveRoles([for (final r in roles) if (r.key != widget.role.key) r]);
    ref.read(staffRevisionProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.role.label),
        actions: [
          if (!widget.role.builtIn)
            IconButton(tooltip: l10n.staffRoleDelete, icon: const Icon(Icons.delete_outline), onPressed: _delete),
          TextButton(onPressed: _saving ? null : _save, child: Text(l10n.save)),
        ],
      ),
      body: SdPage(children: [
        TextField(controller: _label, decoration: InputDecoration(labelText: l10n.staffRoleName)),
        const SizedBox(height: SdSpace.lg),
        if (_isAdmin)
          Text(l10n.staffRoleAdminNote, style: theme.textTheme.bodySmall)
        else
          for (final (group, perms) in Permissions.groups) ...[
            Text(permissionGroupLabel(l10n, group), style: theme.textTheme.titleSmall),
            for (final p in perms)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(permissionLabel(l10n, p)),
                value: _perms.contains(p),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _perms.add(p);
                  } else {
                    _perms.remove(p);
                  }
                }),
              ),
            const SizedBox(height: SdSpace.md),
          ],
      ]),
    );
  }
}
