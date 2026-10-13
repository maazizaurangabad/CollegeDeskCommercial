import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../platform/modules/module_providers.dart';
import 'shell/app_shell.dart';

/// Routes come from the module registry: each installed module brings
/// its own page and sub-pages. A switched-off module redirects home.
final routerProvider = Provider<GoRouter>((ref) {
  final registry = ref.watch(moduleRegistryProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final owner = registry.forLocation(state.uri.path);
      if (owner == null) return '/';
      final visible = ref.read(visibleModulesProvider);
      return visible.any((m) => m.id == owner.id) ? null : '/';
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          for (final module in registry.installed)
            GoRoute(
              path: module.route,
              pageBuilder: (context, state) => NoTransitionPage(child: module.builder(context)),
              routes: module.subRoutes,
            ),
        ],
      ),
    ],
  );
});
