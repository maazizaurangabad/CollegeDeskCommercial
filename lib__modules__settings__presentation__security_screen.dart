import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../app/lock/lock_controller.dart';
import '../../../app/lock/lock_screens.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/staff/staff_providers.dart';
import '../../../platform/workspace/workspace_actions.dart';
import '../../../platform/workspace/workspace_registry.dart';
import 'settings_page_header.dart';

class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lock = ref.watch(lockControllerProvider);
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => SdPage(
        children: [
          SettingsPageHeader(title: l10n.settingsSecurity),
          SdCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: Text(l10n.securityPin),
                  trailing: SdButton(
                    label: lock.hasPin ? l10n.pinChange : l10n.pinSet,
                    variant: SdButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (routeContext) => PinSetupScreen(
                        controller: lock,
                        isChange: lock.hasPin,
                        onDone: () => Navigator.of(routeContext).pop(),
                      ),
                    )),
                  ),
                ),
                const Divider(indent: SdSpace.lg),
                FutureBuilder<bool>(
                  future: LocalAuthentication().isDeviceSupported().catchError((Object _) => false),
                  builder: (context, snapshot) {
                    final supported = snapshot.data ?? false;
                    return SwitchListTile(
                      secondary: const Icon(Icons.fingerprint),
                      title: Text(l10n.securityBiometric),
                      subtitle: supported ? null : Text(l10n.securityBiometricNone),
                      value: lock.biometricEnabled && supported,
                      onChanged: supported && lock.hasPin ? (v) => lock.setBiometric(v) : null,
                    );
                  },
                ),
                if (lock.biometricEnabled && lock.hasPin) _BiometricUser(lock: lock),
                const Divider(indent: SdSpace.lg),
                Padding(
                  padding: const EdgeInsets.fromLTRB(SdSpace.lg, SdSpace.lg, SdSpace.lg, 0),
                  child: SdSelectField<int>(
                    label: l10n.securityAutoLock,
                    value: lock.timeoutMinutes,
                    options: [
                      (0, l10n.securityImmediately),
                      for (final m in const [1, 5, 15, 30]) (m, l10n.securityMinutes(m)),
                    ],
                    onChanged: (v) => lock.setTimeout(v ?? lock.timeoutMinutes),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SdSpace.xl),
          if (lock.hasPin)
            Wrap(
              spacing: SdSpace.sm,
              runSpacing: SdSpace.sm,
              children: [
                SdButton(label: l10n.securityLockNow, icon: Icons.lock_outline, onPressed: lock.lockNow),
                FutureBuilder<List<WorkspaceInfo>>(
                  future: ref.read(workspaceActionsProvider).listWorkspaces(),
                  builder: (context, snapshot) {
                    final hasReal = snapshot.data?.any((w) => !w.isDemo) ?? true;
                    return SdButton(
                      label: l10n.pinRemove,
                      variant: SdButtonVariant.text,
                      onPressed: hasReal
                          ? () => SdToast.show(context, l10n.pinRemoveBlocked)
                          : () async {
                              await lock.store.removePin();
                              lock.pinRemoved();
                            },
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Whose fingerprint opens the app on this device: the administrator or
/// one staff member.
class _BiometricUser extends ConsumerStatefulWidget {
  const _BiometricUser({required this.lock});

  final LockController lock;

  @override
  ConsumerState<_BiometricUser> createState() => _BiometricUserState();
}

class _BiometricUserState extends ConsumerState<_BiometricUser> {
  String _who = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.lock.store.biometricUserId().then((id) {
      if (mounted) {
        setState(() {
          _who = id ?? '';
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final staff = ref.watch(staffListProvider).valueOrNull ?? const [];
    final people = [
      ('', l10n.staffAdminName),
      for (final m in staff)
        if (m.active && m.id != null) (m.id!, m.name),
    ];
    if (!_loaded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, SdSpace.md),
      child: SdSelectField<String>(
        label: l10n.securityBiometricUser,
        value: people.any((p) => p.$1 == _who) ? _who : '',
        options: people,
        onChanged: (v) async {
          final id = v ?? '';
          setState(() => _who = id);
          await widget.lock.store.setBiometricUserId(id.isEmpty ? null : id);
        },
      ),
    );
  }
}
