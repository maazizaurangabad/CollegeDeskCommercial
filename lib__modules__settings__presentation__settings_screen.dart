import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../core/database/app_database.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/modules/module_providers.dart';
import '../../../platform/organization/organization_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return SdPage(
      children: [
        Text(l10n.settingsTitle, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: SdSpace.xl),
        SdSection(
          title: l10n.settingsInstitutionGroup,
          child: _Group(children: [
            _Tile(
              icon: Icons.apartment_outlined,
              title: l10n.settingsInstitutionProfile,
              subtitle: ref.watch(activeOrganizationProvider).name,
              onTap: () => context.go('/settings/institution'),
            ),
            _Tile(
              icon: Icons.calendar_month_outlined,
              title: l10n.settingsAcademicYears,
              subtitle: ref.watch(activeOrganizationProvider).activeAcademicYear,
              onTap: () => context.go('/settings/academic-years'),
            ),
            _Tile(
              icon: Icons.account_tree_outlined,
              title: l10n.settingsClassesDivisions,
              onTap: () => context.go('/settings/classes'),
            ),
            _Tile(
              icon: Icons.tune_outlined,
              title: l10n.settingsStudentFields,
              subtitle: l10n.settingsStudentFieldsSubtitle,
              onTap: () => context.go('/settings/student-fields'),
            ),
            if (ref.watch(enabledModulesProvider).contains('attendance'))
              _Tile(
                icon: Icons.fact_check_outlined,
                title: l10n.settingsAttendance,
                subtitle: l10n.settingsAttendanceSubtitle,
                onTap: () => context.go('/settings/attendance'),
              ),
            _Tile(
              icon: Icons.history_outlined,
              title: l10n.settingsImports,
              subtitle: l10n.settingsImportsSubtitle,
              onTap: () => context.go('/settings/imports'),
            ),
            _Tile(
              icon: Icons.delete_outline,
              title: l10n.settingsRecycleBin,
              onTap: () => context.go('/settings/recycle-bin'),
            ),
          ]),
        ),
        const SizedBox(height: SdSpace.xl),
        SdSection(
          title: l10n.settingsAppGroup,
          child: _Group(children: [
            _Tile(
              icon: Icons.extension_outlined,
              title: l10n.settingsModules,
              subtitle: l10n.settingsModulesSubtitle,
              onTap: () => context.go('/settings/modules'),
            ),
            _Tile(icon: Icons.palette_outlined, title: l10n.settingsAppearance, onTap: () => _pickTheme(context)),
            _Tile(
              icon: Icons.storage_outlined,
              title: l10n.settingsDataStorage,
              subtitle: ref.watch(startupStateProvider).encrypted ? l10n.dataEncryptionOn : l10n.dataEncryptionOff,
              onTap: () => _showDataInfo(context, ref),
            ),
            _Tile(icon: Icons.backup_outlined, title: l10n.settingsBackup, onTap: () => context.go('/settings/backup')),
            _Tile(icon: Icons.lock_outline, title: l10n.settingsSecurity, onTap: () => context.go('/settings/security')),
            _Tile(
              icon: Icons.health_and_safety_outlined,
              title: l10n.settingsDataHealth,
              subtitle: l10n.settingsDataHealthSubtitle,
              onTap: () => context.go('/settings/data-health'),
            ),
          ]),
        ),
        const SizedBox(height: SdSpace.xl),
        _Group(children: [
          _Tile(
            icon: Icons.info_outline,
            title: l10n.settingsAbout,
            onTap: () => showAboutDialog(
              context: context,
              applicationName: l10n.appTitle,
              applicationVersion: '0.8.0 (build 2b)',
            ),
          ),
        ]),
      ],
    );
  }

  void _showDataInfo(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final startup = ref.read(startupStateProvider);
    SdSheet.show<void>(
      context,
      title: l10n.settingsDataStorage,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(startup.encrypted ? Icons.lock_outline : Icons.lock_open_outlined),
            title: Text(startup.encrypted ? l10n.dataEncryptionOn : l10n.dataEncryptionOff),
          ),
          ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: Text(l10n.dataSchemaVersion(AppDatabase.currentSchemaVersion)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.dataBackupNote),
          ),
        ],
      ),
    );
  }

  void _pickTheme(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = {
      ThemeMode.system: l10n.appearanceSystem,
      ThemeMode.light: l10n.appearanceLight,
      ThemeMode.dark: l10n.appearanceDark,
    };
    SdSheet.show<void>(
      context,
      title: l10n.settingsAppearance,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(themeModeProvider);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in options.entries)
                ListTile(
                  title: Text(entry.value),
                  trailing: entry.key == current ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    ref.read(themeModeProvider.notifier).change(entry.key).catchError((Object _) {
                      if (context.mounted) SdToast.show(context, l10n.saveFailed);
                    });
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SdCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: SdSpace.lg),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.onTap, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
