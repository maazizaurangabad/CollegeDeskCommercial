import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'migrations.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// One database per institution (workspace). Every table carries
/// organization_id as well, so the same rows can later live in a shared
/// cloud database without changes.
@DriftDatabase(tables: [
  Organizations,
  ModuleSettings,
  AppSettings,
  AuditEntries,
  OutboxEntries,
  MigrationHistory,
  AcademicYears,
  Programs,
  Divisions,
  Students,
  Guardians,
  StudentGuardians,
  StudentIdentifiers,
  Enrollments,
  FieldDefinitions,
  Sequences,
  ImportBatches,
  ImportRows,
  AttendanceCodes,
  AttendanceSessions,
  AttendanceRecords,
  CalendarDays,
  Certificates,
  MessageLogs,
  FeeHeads,
  FeeStructures,
  FeeStructureItems,
  FeeDueDates,
  StudentFeeAdjustments,
  FeeReceipts,
  FeeReceiptLines,
  Subjects,
  Exams,
  SubjectChoices,
  Marks,
  StudentDocuments,
  StaffMembers,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Bump this and add a step in migrations.dart for every schema change.
  static const int currentSchemaVersion = 12;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await createExtraIndexes(m);
        },
        onUpgrade: (m, from, to) async {
          for (var version = from; version < to; version++) {
            await applyMigrationStep(this, m, version);
            await into(migrationHistory).insert(MigrationHistoryCompanion.insert(
              fromVersion: version,
              toVersion: version + 1,
              migratedAt: DateTime.now().toUtc(),
            ));
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          if (details.wasCreated || details.hadUpgrade) {
            final check = await customSelect('PRAGMA quick_check').getSingle();
            final result = check.data.values.first;
            if (result != 'ok') {
              throw StateError('Database check failed after opening: $result');
            }
          }
        },
      );

  /// Opens an encrypted database file. Refuses to continue if the
  /// encrypted SQLite build is missing, so data is never written unencrypted.
  static QueryExecutor openEncrypted(File file, String hexKey) {
    return NativeDatabase.createInBackground(
      file,
      setup: (raw) {
        if (raw.select('PRAGMA cipher;').isEmpty) {
          throw StateError('Encrypted SQLite is not available in this build.');
        }
        raw.execute("PRAGMA key = '$hexKey';");
        // Fails immediately if the key is wrong.
        raw.select('SELECT count(*) FROM sqlite_master;');
        raw.execute('PRAGMA journal_mode = WAL;');
      },
    );
  }
}
