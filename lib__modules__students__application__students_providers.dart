import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/app_settings_repository.dart';
import '../../../platform/data/data_providers.dart';
import '../data/field_definition_repository.dart';
import '../data/student_repository.dart';
import '../domain/record_completeness.dart';
import '../import/import_report.dart';
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

/// Which checks count in "Record completeness" (Settings > Student fields).
abstract final class CompletenessSettings {
  static const settingKey = 'students.completeness_checks';

  static Future<Set<CompletenessCheck>> load(AppSettingsRepository settings) async =>
      RecordCompleteness.decodeChecks(await settings.getValue(settingKey));

  static Future<void> save(AppSettingsRepository settings, Set<CompletenessCheck> checks) =>
      settings.setValue(settingKey, RecordCompleteness.encodeChecks(checks));
}

/// Whether every student needs a mother's name (board exam forms).
abstract final class StudentFormSettings {
  static const motherRequiredKey = 'students.mother_required';

  static Future<bool> motherRequired(AppSettingsRepository settings) async =>
      (await settings.getValue(motherRequiredKey)) != 'false';

  static Future<void> setMotherRequired(AppSettingsRepository settings, bool value) =>
      settings.setValue(motherRequiredKey, '$value');
}

final motherRequiredProvider = FutureProvider<bool>((ref) {
  ref.watch(studentsRevisionProvider);
  return StudentFormSettings.motherRequired(ref.watch(appSettingsRepositoryProvider));
});

/// The last import's report: kept until the user closes it or starts a
/// new import (in memory only, never saved: it holds the sheet's cells).
final lastImportReportProvider = StateProvider<ImportReport?>((ref) => null);

/// A skipped import row being added by hand: its row number and what the
/// sheet had, to fill the Add Student form.
final importPrefillProvider = StateProvider<({int rowNumber, StudentDraft draft})?>((ref) => null);

final completenessChecksProvider = FutureProvider<Set<CompletenessCheck>>((ref) {
  ref.watch(studentsRevisionProvider);
  return CompletenessSettings.load(ref.watch(appSettingsRepositoryProvider));
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
