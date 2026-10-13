import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/app_settings_repository.dart';
import '../../../platform/data/data_providers.dart';
import '../data/field_definition_repository.dart';
import '../data/student_repository.dart';
import '../domain/student_models.dart';
import '../import/import_repository.dart';

final studentRepositoryProvider = Provider<StudentRepository>(
  (ref) => StudentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(sessionProvider),
    ref.watch(startupStateProvider).fieldCipher,
  ),
);

final fieldDefinitionRepositoryProvider = Provider<FieldDefinitionRepository>(
  (ref) => FieldDefinitionRepository(ref.watch(appDatabaseProvider), ref.watch(sessionProvider)),
);

/// Bumped after every student change so lists and the dashboard reload.
final studentsRevisionProvider = StateProvider<int>((ref) => 0);

final extraFieldsProvider = FutureProvider<List<ExtraFieldDefinition>>((ref) {
  ref.watch(studentsRevisionProvider);
  return ref.watch(fieldDefinitionRepositoryProvider).listForStudents();
});

final activeStudentCountProvider = FutureProvider<int>((ref) {
  ref.watch(studentsRevisionProvider);
  return ref.watch(studentRepositoryProvider).countActive();
});

/// Category choices, editable per institution in Settings > Student fields.
abstract final class StudentCategories {
  static const settingKey = 'students.categories';

  static Future<List<String>> load(AppSettingsRepository settings) async {
    final saved = await settings.getValue(settingKey);
    if (saved == null) return StudentChoices.defaultCategories;
    try {
      return (jsonDecode(saved) as List<dynamic>).map((e) => '$e').toList();
    } catch (_) {
      return StudentChoices.defaultCategories;
    }
  }

  static Future<void> save(AppSettingsRepository settings, List<String> categories) =>
      settings.setValue(settingKey, jsonEncode(categories.map((c) => c.trim()).where((c) => c.isNotEmpty).toList()));
}

final studentCategoriesProvider = FutureProvider<List<String>>((ref) {
  ref.watch(studentsRevisionProvider);
  return StudentCategories.load(ref.watch(appSettingsRepositoryProvider));
});

final importRepositoryProvider = Provider<ImportRepository>(
  (ref) => ImportRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(sessionProvider),
    ref.watch(studentRepositoryProvider),
    ref.watch(academicRepositoryProvider),
    ref.watch(appSettingsRepositoryProvider),
  ),
);
