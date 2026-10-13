import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';

/// Everything the app shell needs to know about a module.
/// A new module (Fees, Results...) adds one descriptor; navigation,
/// settings and routing pick it up without other code changing.
@immutable
class ModuleDescriptor {
  const ModuleDescriptor({
    required this.id,
    required this.title,
    required this.icon,
    required this.selectedIcon,
    required this.route,
    required this.navOrder,
    required this.builder,
    this.version = '0.1.0',
    this.isCore = false,
    this.defaultEnabled = true,
    this.requiredPermissions = const {},
    this.dependsOn = const [],
    this.subRoutes = const [],
  });

  /// Stable id, e.g. 'attendance'. Never changes once released.
  final String id;

  /// Display name, read from translations.
  final String Function(AppLocalizations l10n) title;

  final IconData icon;
  final IconData selectedIcon;

  /// Top-level route, e.g. '/students'. The dashboard owns '/'.
  final String route;

  /// Position in navigation; lower comes first.
  final int navOrder;

  /// Builds the module's main screen.
  final WidgetBuilder builder;

  final String version;

  /// Core modules (Dashboard, Settings) cannot be switched off.
  final bool isCore;

  /// Enabled when an institution is first set up.
  final bool defaultEnabled;

  /// The user needs all of these to see the module.
  final Set<String> requiredPermissions;

  /// Ids of modules this one needs, e.g. attendance depends on students.
  final List<String> dependsOn;

  /// Nested pages, e.g. '/settings/modules'. Paths are relative.
  final List<RouteBase> subRoutes;
}
