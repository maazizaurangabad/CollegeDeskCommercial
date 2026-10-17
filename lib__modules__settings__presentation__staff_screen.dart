import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/pin_hasher.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/staff/staff_models.dart';
import '../../../platform/staff/staff_providers.dart';
import '../../../platform/staff/staff_repository.dart';
import 'settings_page_header.dart';

/// Settings > Staff: everyone who logs in with their own PIN.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final staff = ref.watch(staffListProvider);
    final roles = ref.watch(staffRolesProvider).valueOrNull ?? StaffRoles.defaults;
    final roleLabel = {for (final r in roles) r.key: r.label};

    return SdPage(
      children: [
        SettingsPageHeader(
          title: l10n.staffTitle,
          trailing: SdButton(
            label: l10n.staffAdd,
            icon: Icons.person_add_alt,
            onPressed: () => StaffEditDialog.show(context, ref, null),
          ),
        ),
        Text(l10n.staffIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: SdSpace.lg),
        staff.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(l10n.saveFailed),
          data: (list) => list.isEmpty
              ? SdEmptyState(
                  icon: Icons.badge_outlined,
                  title: l10n.staffEmptyTitle,
                  message: l10n.staffEmpty,
                  action: SdButton(
                    label: l10n.staffAdd,
                    icon: Icons.person_add_alt,
                    onPressed: () => StaffEditDialog.show(context, ref, null),
                  ),
                )
              : SdCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) const Divider(indent: SdSpace.lg),
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(list[i].name.isEmpty ? '?' : list[i].name.characters.first.toUpperCase()),
                        ),
                        title: Text(list[i].name),
                        subtitle: Text([
                          roleLabel[list[i].roleKey] ?? list[i].roleKey,
                          if ((list[i].mobile ?? '').isNotEmpty) list[i].mobile!,
                          if (!list[i].active) l10n.staffInactive,
                        ].join(' · ')),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => StaffEditDialog.show(context, ref, list[i]),
                      ),
                    ],
                  ]),
                ),
        ),
        const SizedBox(height: SdSpace.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: SdButton(
            label: l10n.staffRoles,
            icon: Icons.admin_panel_settings_outlined,
            variant: SdButtonVariant.secondary,
            onPressed: () => context.go('/settings/staff/roles'),
          ),
        ),
        const SizedBox(height: SdSpace.md),
        Text(l10n.staffAdminNote, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Add or change one staff member: name, mobile, role, PIN, active.
class StaffEditDialog extends ConsumerStatefulWidget {
  const StaffEditDialog({super.key, this.member});

  final StaffMember? member;

  static Future<void> show(BuildContext context, WidgetRef ref, StaffMember? member) =>
      showDialog<void>(context: context, builder: (_) => StaffEditDialog(member: member));

  @override
  ConsumerState<StaffEditDialog> createState() => _StaffEditDialogState();
}

class _StaffEditDialogState extends ConsumerState<StaffEditDialog> {
  late final _name = TextEditingController(text: widget.member?.name ?? '');
  late final _mobile = TextEditingController(text: widget.member?.mobile ?? '');
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  late String _role = widget.member?.roleKey ?? 'clerk';
  late bool _active = widget.member?.active ?? true;
  String? _nameError;
  String? _pinError;
  bool _saving = false;

  bool get _isNew => widget.member == null;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final pin = _pin.text.trim();
    setState(() {
      _nameError = _name.text.trim().isEmpty ? l10n.staffErrName : null;
      _pinError = null;
      if (_isNew || pin.isNotEmpty) {
        if (!PinHasher.isValidPin(pin)) {
          _pinError = l10n.staffErrPin;
        } else if (pin != _pin2.text.trim()) {
          _pinError = l10n.pinMismatch;
        }
      }
    });
    if (_nameError != null || _pinError != null) return;
    setState(() => _saving = true);
    try {
      final base = widget.member ?? StaffMember(name: '', roleKey: _role);
      await ref.read(staffRepositoryProvider).save(
            base.copyWith(name: _name.text.trim(), mobile: _mobile.text.trim(), roleKey: _role, active: _active),
            pin: pin.isEmpty ? null : pin,
          );
      ref.read(staffRevisionProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop();
    } on StaffException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SdToast.show(context, switch (e.issue) {
        StaffIssue.emptyName => l10n.staffErrName,
        StaffIssue.badPin => l10n.staffErrPin,
        _ => l10n.saveFailed,
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      SdToast.show(context, l10n.saveFailed);
    }
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final ok = await SdDialog.confirm(
      context,
      title: l10n.staffRemoveTitle,
      message: l10n.staffRemoveMessage(widget.member!.name),
      confirmLabel: l10n.staffRemove,
      cancelLabel: l10n.cancel,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(staffRepositoryProvider).remove(widget.member!.id!);
      ref.read(staffRevisionProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roles = ref.watch(staffRolesProvider).valueOrNull ?? StaffRoles.defaults;
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)];
    return AlertDialog(
      title: Text(_isNew ? l10n.staffAdd : l10n.staffEdit),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.staffName, errorText: _nameError),
              ),
              const SizedBox(height: SdSpace.md),
              TextField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l10n.fieldMobile),
              ),
              const SizedBox(height: SdSpace.md),
              SdSelectField<String>(
                label: l10n.staffRole,
                value: roles.any((r) => r.key == _role) ? _role : null,
                options: [for (final r in roles) (r.key, r.label)],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: SdSpace.md),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: InputDecoration(
                  labelText: _isNew ? l10n.staffPin : l10n.staffNewPin,
                  helperText: _isNew ? l10n.staffPinHint : l10n.staffNewPinHint,
                  errorText: _pinError,
                ),
              ),
              const SizedBox(height: SdSpace.md),
              TextField(
                controller: _pin2,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: InputDecoration(labelText: l10n.pinConfirm),
              ),
              if (!_isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.staffActive),
                  subtitle: Text(l10n.staffActiveHint),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_isNew)
          TextButton(
            onPressed: _saving ? null : _remove,
            child: Text(l10n.staffRemove, style: TextStyle(color: SdColors.of(context).absent)),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(onPressed: _saving ? null : _save, child: Text(l10n.save)),
      ],
    );
  }
}
