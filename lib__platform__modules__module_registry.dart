import 'module_descriptor.dart';

/// The list of modules installed in this build, and the rules for which
/// ones a given institution and user can see.
class ModuleRegistry {
  ModuleRegistry(List<ModuleDescriptor> modules)
      : installed = List.unmodifiable([...modules]..sort((a, b) => a.navOrder.compareTo(b.navOrder))) {
    _validate();
  }

  final List<ModuleDescriptor> installed;

  ModuleDescriptor? byId(String id) {
    for (final m in installed) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The module that owns [path], e.g. '/settings/modules' -> settings.
  ModuleDescriptor? forLocation(String path) {
    ModuleDescriptor? best;
    for (final m in installed) {
      final matches = m.route == '/' ? path == '/' : (path == m.route || path.startsWith('${m.route}/'));
      if (matches && (best == null || m.route.length > best.route.length)) best = m;
    }
    return best;
  }

  /// Modules shown to this user: installed, enabled for the institution
  /// (or core), dependencies enabled, and permitted.
  List<ModuleDescriptor> visible({
    required Set<String> enabledIds,
    required bool Function(String permission) can,
  }) {
    bool isOn(ModuleDescriptor m) => m.isCore || enabledIds.contains(m.id);
    return installed.where((m) {
      if (!isOn(m)) return false;
      for (final dep in m.dependsOn) {
        final d = byId(dep);
        if (d == null || !isOn(d)) return false;
      }
      return m.requiredPermissions.every(can);
    }).toList();
  }

  void _validate() {
    final ids = <String>{};
    final routes = <String>{};
    for (final m in installed) {
      if (!ids.add(m.id)) throw ArgumentError('Duplicate module id: ${m.id}');
      if (!routes.add(m.route)) throw ArgumentError('Duplicate module route: ${m.route}');
      if (!m.route.startsWith('/')) throw ArgumentError('Module route must start with /: ${m.route}');
    }
    for (final m in installed) {
      for (final dep in m.dependsOn) {
        if (!ids.contains(dep)) throw ArgumentError('Module ${m.id} depends on missing module $dep');
      }
    }
  }
}
