import 'package:drift/drift.dart';

import 'app_database.dart';

/// Upgrades the schema from [fromVersion] to [fromVersion] + 1.
///
/// Rules (blueprint section 27):
/// - Never edit a released step; add a new one.
/// - Prefer adding columns and tables; remove old ones only later.
/// - Every step has a test in test/core/migration_test.dart.
Future<void> applyMigrationStep(AppDatabase db, Migrator m, int fromVersion) async {
  switch (fromVersion) {
    case 1:
      // v1 -> v2: institutions can record their UDISE code.
      await m.addColumn(db.organizations, db.organizations.udiseCode);
    case 2:
      // v2 -> v3: institution details, academic years, classes and divisions.
      await m.addColumn(db.organizations, db.organizations.address);
      await m.addColumn(db.organizations, db.organizations.state);
      await m.addColumn(db.organizations, db.organizations.website);
      await m.addColumn(db.organizations, db.organizations.logoFileName);
      await m.addColumn(db.organizations, db.organizations.programLabel);
      await m.addColumn(db.organizations, db.organizations.divisionLabel);
      await m.createTable(db.academicYears);
      await m.createTable(db.programs);
      await m.createTable(db.divisions);
    case 3:
      // v3 -> v4: students, guardians, identifiers, enrollments, extra fields.
      await m.createTable(db.students);
      await m.createTable(db.guardians);
      await m.createTable(db.studentGuardians);
      await m.createTable(db.studentIdentifiers);
      await m.createTable(db.enrollments);
      await m.createTable(db.fieldDefinitions);
      await m.createTable(db.sequences);
      await _createIndexes(m, _v4Indexes);
    case 4:
      // v4 -> v5: import history for Excel and photo imports (with undo).
      await m.createTable(db.importBatches);
      await m.createTable(db.importRows);
      await _createIndexes(m, _v5Indexes);
    default:
      throw StateError('No migration step from schema version $fromVersion');
  }
}

/// Indexes declared in SQL, grouped by the schema version that added
/// their tables. New databases get all of them in onCreate.
final _v4Indexes = [
  Index('enrollments_by_division',
      'CREATE INDEX IF NOT EXISTS enrollments_by_division ON enrollments (division_id, academic_year_id, status)'),
  Index('enrollments_by_student', 'CREATE INDEX IF NOT EXISTS enrollments_by_student ON enrollments (student_id)'),
  Index('identifiers_by_value',
      'CREATE INDEX IF NOT EXISTS identifiers_by_value ON student_identifiers (organization_id, id_type, id_value)'),
  Index('students_by_org', 'CREATE INDEX IF NOT EXISTS students_by_org ON students (organization_id, status)'),
];

final _v5Indexes = [
  Index('import_rows_by_batch', 'CREATE INDEX IF NOT EXISTS import_rows_by_batch ON import_rows (batch_id)'),
];

Future<void> _createIndexes(Migrator m, List<Index> indexes) async {
  for (final index in indexes) {
    await m.createIndex(index);
  }
}

/// For a brand-new database.
Future<void> createExtraIndexes(Migrator m) => _createIndexes(m, [..._v4Indexes, ..._v5Indexes]);
