import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/theme/app_theme.dart';
import '../l10n/gen/app_localizations.dart';
import '../platform/organization/organization_providers.dart';
import 'router.dart';

class ShikshaDeskApp extends ConsumerWidget {
  const ShikshaDeskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final org = ref.watch(activeOrganizationProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildSdTheme(brand: org.brandColor, brightness: Brightness.light),
      darkTheme: buildSdTheme(brand: org.brandColor, brightness: Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
