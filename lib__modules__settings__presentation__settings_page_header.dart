import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Back arrow and title for pages inside Settings.
class SettingsPageHeader extends StatelessWidget {
  const SettingsPageHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: Row(
        children: [
          IconButton(
            tooltip: AppLocalizations.of(context).back,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/settings'),
          ),
          const SizedBox(width: SdSpace.xs),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Runs a save action and shows a readable message if it is refused.
Future<bool> runWithFeedback(
  BuildContext context,
  Future<void> Function() action,
  String Function(Object error) message,
) async {
  try {
    await action();
    return true;
  } catch (error) {
    if (context.mounted) SdToast.show(context, message(error));
    return false;
  }
}
