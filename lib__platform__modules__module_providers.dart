import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/attendance/attendance_module.dart';
import '../../modules/certificates/certificates_module.dart';
import '../../modules/dashboard/dashboard_module.dart';
import '../../modules/reports/reports_module.dart';
import '../../modules/search/search_module.dart';
import '../../modules/settings/settings_module.dart';
import '../../modules/students/students_module.dart';
import '../data/data_providers.dart';
import '../data/module_settings_repository.dart';
import '../organization/organization_providers.dart';
import 'module_descriptor.dart';
import 'module_registry.dart';

/// Every module compiled into this build. Add new modules here.
ModuleRegistry buildModuleRegistry() =>
    ModuleRegistry([
      dashboardModule,
      searchModule,
      studentsModule,
      attendanceModule,
      certificatesModule,
      reportsModule,
      settingsModule,
    ]);

final moduleRegistryProvider = Provider<ModuleRegistry>((ref) => buildModuleRegistry());

/// Modules this institution has switched on, saved in its database.
final enabledModulesProvider = StateNotifierProvider<EnabledModulesNotifier, Set<String>>(
  (ref) => EnabledModulesNotifier(
    ref.watch(startupStateProvider).enabledModules,
    ref.watch(moduleSettingsRepositoryProvider),
  ),
);

class EnabledModulesNotifier extends StateNotifier<Set<String>> {
  EnabledModulesNotifier(super.initial, this._repository);

  final ModuleSettingsRepository _repository;

  Future<void> setEnabled(String id, bool enabled) async {
    final previous = state;
    state = enabled ? {...state, id} : ({...state}..remove(id));
    try {
      await _repository.setEnabled(id, enabled);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

/// What the navigation shows right now.
final visibleModulesProvider = Provider<List<ModuleDescriptor>>((ref) {
  final registry = ref.watch(moduleRegistryProvider);
  return registry.visible(
    enabledIds: ref.watch(enabledModulesProvider),
    can: ref.watch(permissionCheckerProvider),
  );
});
