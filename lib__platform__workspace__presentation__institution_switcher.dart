import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../data/data_providers.dart';
import '../workspace_actions.dart';
import '../workspace_registry.dart';
import 'setup_wizard_screen.dart';

/// Bottom sheet listing the institutions on this device.
abstract final class InstitutionSwitcher {
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(workspaceActionsProvider);
    final currentId = ref.read(sessionProvider).organizationId;
    final workspaces = await actions.listWorkspaces();
    if (!context.mounted) return;

    await SdSheet.show<void>(
      context,
      title: l10n.switcherTitle,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          for (final w in workspaces) _row(context, sheetContext, l10n, actions, w, w.id == currentId),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add_business_outlined),
            title: Text(l10n.switcherAdd),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => const SetupWizardScreen(),
              ));
            },
          ),
        ],
      ),
    );
  }

  static Widget _row(
    BuildContext context,
    BuildContext sheetContext,
    AppLocalizations l10n,
    WorkspaceActions actions,
    WorkspaceInfo w,
    bool isCurrent,
  ) {
    return ListTile(
      leading: Icon(w.isDemo ? Icons.science_outlined : Icons.apartment_outlined),
      title: Text(w.name),
      subtitle: isCurrent ? Text(l10n.switcherOpenNow) : (w.isDemo ? Text(l10n.switcherDemoTag) : null),
      trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
      onTap: () async {
        Navigator.of(sheetContext).pop();
        if (isCurrent) return;
        final messenger = ScaffoldMessenger.of(context);
        try {
          await actions.switchTo(w.id);
        } catch (_) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.switchFailed)));
        }
      },
    );
  }
}
