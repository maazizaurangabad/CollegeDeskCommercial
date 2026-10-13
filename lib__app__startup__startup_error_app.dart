import 'package:flutter/material.dart';

import '../../design_system/components/components.dart';
import '../../l10n/gen/app_localizations.dart';

/// Shown instead of the app when the data cannot be opened safely.
/// Says what happened and that nothing was changed.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.details});

  final String details;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildSdTheme(brand: SdPalette.ink, brightness: Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            body: SafeArea(
              child: SdEmptyState(
                icon: Icons.lock_outline,
                title: l10n.startupErrorTitle,
                message: '${l10n.startupErrorMessage}\n\n$details',
              ),
            ),
          );
        },
      ),
    );
  }
}
