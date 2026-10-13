import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/modules/module_providers.dart';

/// Lets the institution switch modules on or off.
/// Switching off hides a module; it never deletes its data.
class ModulesSettingsScreen extends ConsumerWidget {
  const ModulesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(moduleRegistryProvider);
    final enabled = ref.watch(enabledModulesProvider);
    final theme = Theme.of(context);

    return SdPage(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.back,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/settings'),
            ),
            const SizedBox(width: SdSpace.xs),
            Text(l10n.modulesTitle, style: theme.textTheme.headlineSmall),
          ],
        ),
        const SizedBox(height: SdSpace.lg),
        SdCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < registry.installed.length; i++) ...[
                if (i > 0) const Divider(indent: SdSpace.lg),
                Builder(builder: (context) {
                  final m = registry.installed[i];
                  final on = m.isCore || enabled.contains(m.id);
                  return SwitchListTile(
                    secondary: Icon(m.icon),
                    title: Text(m.title(l10n)),
                    subtitle: Text(m.isCore ? l10n.modulesAlwaysOn : l10n.modulesVersion(m.version)),
                    value: on,
                    onChanged: m.isCore
                        ? null
                        : (value) => ref.read(enabledModulesProvider.notifier).setEnabled(m.id, value).catchError((Object _) {
                              if (context.mounted) SdToast.show(context, l10n.saveFailed);
                            }),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
