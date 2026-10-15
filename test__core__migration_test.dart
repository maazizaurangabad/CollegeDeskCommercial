import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// The database exactly as schema version 1 created it.
const _schemaV1 = [
  '''CREATE TABLE organizations (id TEXT NOT NULL PRIMARY KEY, organization_id TEXT NOT NULL,
     created_at TEXT NOT NULL, updated_at TEXT NOT NULL, created_by TEXT NULL, updated_by TEXT NULL,
     deleted_at TEXT NULL, row_version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL,
     name TEXT NOT NULL, short_name TEXT NOT NULL, institution_type TEXT NOT NULL,
     city TEXT NOT NULL DEFAULT '', board TEXT NULL, medium TEXT NULL, phone TEXT NULL, email TEXT NULL,
     brand_color INTEGER NOT NULL, active_academic_year TEXT NOT NULL)''',
  '''CREATE TABLE module_settings (id TEXT NOT NULL PRIMARY KEY, organization_id TEXT NOT NULL,
     created_at TEXT NOT NULL, updated_at TEXT NOT NULL, created_by TEXT NULL, updated_by TEXT NULL,
     deleted_at TEXT NULL, row_version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL,
     module_id TEXT NOT NULL, enabled INTEGER NOT NULL, UNIQUE (organization_id, module_id))''',
  '''CREATE TABLE app_settings (id TEXT NOT NULL PRIMARY KEY, organization_id TEXT NOT NULL,
     created_at TEXT NOT NULL, updated_at TEXT NOT NULL, created_by TEXT NULL, updated_by TEXT NULL,
     deleted_at TEXT NULL, row_version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL,
     setting_key TEXT NOT NULL, setting_value TEXT NOT NULL, UNIQUE (organization_id, setting_key))''',
  '''CREATE TABLE audit_entries (id TEXT NOT NULL PRIMARY KEY, organization_id TEXT NOT NULL,
     entity TEXT NOT NULL, entity_id TEXT NOT NULL, action TEXT NOT NULL, changes TEXT NOT NULL,
     user_id TEXT NULL, device_id TEXT NOT NULL, at TEXT NOT NULL)''',
  '''CREATE TABLE outbox_entries (id TEXT NOT NULL PRIMARY KEY, organization_id TEXT NOT NULL,
     target_table TEXT NOT NULL, row_id TEXT NOT NULL, operation TEXT NOT NULL, payload TEXT NOT NULL,
     created_at TEXT NOT NULL, synced_at TEXT NULL)''',
  '''CREATE TABLE migration_history (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
     from_version INTEGER NOT NULL, to_version INTEGER NOT NULL, migrated_at TEXT NOT NULL)''',
  '''INSERT INTO organizations (id, organization_id, created_at, updated_at, device_id, name,
     short_name, institution_type, brand_color, active_academic_year)
     VALUES ('org-1', 'org-1', '2026-10-01T00:00:00.000Z', '2026-10-01T00:00:00.000Z', 'dev-1',
     'Old Version College', 'Old Version', 'Junior college', 4280110729, '2026-27')''',
  '''INSERT INTO module_settings (id, organization_id, created_at, updated_at, device_id, module_id, enabled)
     VALUES ('ms-1', 'org-1', '2026-10-01T00:00:00.000Z', '2026-10-01T00:00:00.000Z', 'dev-1', 'students', 0)''',
  'PRAGMA user_version = 1',
];

void main() {
  late Directory tempDir;

  setUp(() async => tempDir = await Directory.systemTemp.createTemp('sd_migration_'));
  tearDown(() async => tempDir.delete(recursive: true));

  test('upgrading from version 1 keeps every record and adds the new column', () async {
    final file = File(p.join(tempDir.path, 'v1.db'));
    final raw = sqlite3.open(file.path);
    for (final statement in _schemaV1) {
      raw.execute(statement);
    }
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    final orgs = await db.select(db.organizations).get();
    expect(orgs, hasLength(1));
    expect(orgs.single.name, 'Old Version College');
    expect(orgs.single.udiseCode, isNull);

    final modules = await db.select(db.moduleSettings).get();
    expect(modules.single.enabled, isFalse);

    final history = await (db.select(db.migrationHistory)..orderBy([(t) => OrderingTerm.asc(t.fromVersion)])).get();
    expect(history.map((h) => '${h.fromVersion}->${h.toVersion}'), ['1->2', '2->3', '3->4', '4->5', '5->6', '6->7', '7->8', '8->9', '9->10']);
    expect(history.last.toVersion, AppDatabase.currentSchemaVersion);

    // Tables added in version 3 exist and are empty.
    expect(await db.select(db.academicYears).get(), isEmpty);
    expect(await db.select(db.programs).get(), isEmpty);
    expect(await db.select(db.divisions).get(), isEmpty);
    expect(orgs.single.programLabel, isNull);

    // Tables added in version 4 exist and are empty.
    expect(await db.select(db.students).get(), isEmpty);
    expect(await db.select(db.enrollments).get(), isEmpty);
    expect(await db.select(db.studentIdentifiers).get(), isEmpty);
    expect(await db.select(db.importBatches).get(), isEmpty);
    expect(await db.select(db.attendanceSessions).get(), isEmpty);
    expect(await db.select(db.calendarDays).get(), isEmpty);
    expect(await db.select(db.certificates).get(), isEmpty);
    expect(await db.select(db.messageLogs).get(), isEmpty);
    expect(await db.select(db.feeHeads).get(), isEmpty);
    expect(await db.select(db.feeReceipts).get(), isEmpty);
    expect(await db.select(db.marks).get(), isEmpty);

    await (db.update(db.organizations)..where((t) => t.id.equals('org-1')))
        .write(const OrganizationsCompanion(udiseCode: Value('27191234567')));
    expect((await db.select(db.organizations).getSingle()).udiseCode, '27191234567');
    await db.close();
  });

  test('a brand-new database starts at the current version', () async {
    final file = File(p.join(tempDir.path, 'new.db'));
    final db = AppDatabase(NativeDatabase(file));
    await db.select(db.organizations).get();
    await db.close();

    final raw = sqlite3.open(file.path);
    expect(raw.select('PRAGMA user_version').first['user_version'], AppDatabase.currentSchemaVersion);
    raw.close();
  });
}
