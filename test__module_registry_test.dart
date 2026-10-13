import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/platform/modules/module_descriptor.dart';
import 'package:shiksha_desk/platform/modules/module_registry.dart';

ModuleDescriptor _module(
  String id,
  String route, {
  int order = 0,
  bool core = false,
  List<String> dependsOn = const [],
  Set<String> permissions = const {},
}) {
  return ModuleDescriptor(
    id: id,
    title: (_) => id,
    icon: Icons.circle_outlined,
    selectedIcon: Icons.circle,
    route: route,
    navOrder: order,
    isCore: core,
    dependsOn: dependsOn,
    requiredPermissions: permissions,
    builder: (_) => const SizedBox(),
  );
}

void main() {
  bool allowAll(String _) => true;

  test('modules are sorted by navigation order', () {
    final registry = ModuleRegistry([
      _module('settings', '/settings', order: 1000, core: true),
      _module('dashboard', '/', order: 0, core: true),
      _module('students', '/students', order: 10),
    ]);
    expect(registry.installed.map((m) => m.id), ['dashboard', 'students', 'settings']);
  });

  test('duplicate ids, duplicate routes and missing dependencies are rejected', () {
    expect(() => ModuleRegistry([_module('a', '/a'), _module('a', '/b')]), throwsArgumentError);
    expect(() => ModuleRegistry([_module('a', '/a'), _module('b', '/a')]), throwsArgumentError);
    expect(() => ModuleRegistry([_module('a', '/a', dependsOn: ['missing'])]), throwsArgumentError);
  });

  test('core modules are always visible; others only when enabled', () {
    final registry = ModuleRegistry([
      _module('dashboard', '/', core: true),
      _module('students', '/students', order: 10),
    ]);
    expect(registry.visible(enabledIds: {}, can: allowAll).map((m) => m.id), ['dashboard']);
    expect(registry.visible(enabledIds: {'students'}, can: allowAll).map((m) => m.id), ['dashboard', 'students']);
  });

  test('a module is hidden when its dependency is switched off', () {
    final registry = ModuleRegistry([
      _module('students', '/students', order: 10),
      _module('attendance', '/attendance', order: 20, dependsOn: ['students']),
    ]);
    expect(registry.visible(enabledIds: {'attendance'}, can: allowAll), isEmpty);
    expect(registry.visible(enabledIds: {'attendance', 'students'}, can: allowAll).length, 2);
  });

  test('a module is hidden without its permission', () {
    final registry = ModuleRegistry([_module('fees', '/fees', permissions: {'fees.view'})]);
    expect(registry.visible(enabledIds: {'fees'}, can: (_) => false), isEmpty);
  });

  test('locations map to the module that owns them', () {
    final registry = ModuleRegistry([
      _module('dashboard', '/', core: true),
      _module('settings', '/settings', order: 1000, core: true),
    ]);
    expect(registry.forLocation('/')?.id, 'dashboard');
    expect(registry.forLocation('/settings/modules')?.id, 'settings');
    expect(registry.forLocation('/settingsx'), isNull);
  });
}
