import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/core/session/app_session.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/data/module_settings_repository.dart';
import 'package:shiksha_desk/platform/data/organization_repository.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/workspace_seeder.dart';

import '../test_support.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = newMemoryDatabase());
  tearDown(() => db.close());

  test('a new workspace gets the demo institution and default modules', () async {
    await WorkspaceSeeder(db, testSession).seedDemoIfEmpty(buildModuleRegistry());
    final org = await OrganizationRepository(db, testSession).loadActive();
    expect(org, isNotNull);
    expect(org!.id, testSession.organizationId);
    final modules = await ModuleSettingsRepository(db, testSession).loadAll();
    expect(modules['students'], isTrue);
  });

  test('seeding twice does not duplicate anything', () async {
    final seeder = WorkspaceSeeder(db, testSession);
    await seeder.seedDemoIfEmpty(buildModuleRegistry());
    await seeder.seedDemoIfEmpty(buildModuleRegistry());
    expect(await db.select(db.organizations).get(), hasLength(1));
  });

  test('every change writes an audit entry and an outbox entry', () async {
    final repo = ModuleSettingsRepository(db, testSession);
    await repo.setEnabled('students', true);
    await repo.setEnabled('students', false);

    final row = await (db.select(db.moduleSettings)..where((t) => t.moduleId.equals('students'))).getSingle();
    expect(row.enabled, isFalse);
    expect(row.rowVersion, 2);
    expect(row.updatedBy, testSession.userId);
    expect(row.deviceId, testSession.deviceId);

    final audit = await (db.select(db.auditEntries)..orderBy([(t) => OrderingTerm.asc(t.at)])).get();
    expect(audit, hasLength(2));
    final change = jsonDecode(audit.last.changes) as Map<String, Object?>;
    expect(change['enabled'], {'old': true, 'new': false});

    expect(await db.select(db.outboxEntries).get(), hasLength(2));
  });

  test('saving the same value again records nothing new', () async {
    final repo = AppSettingsRepository(db, testSession);
    await repo.setValue('appearance.theme_mode', 'dark');
    await repo.setValue('appearance.theme_mode', 'dark');
    expect(await repo.getValue('appearance.theme_mode'), 'dark');
    expect(await db.select(db.auditEntries).get(), hasLength(1));
  });

  test('another institution never sees this institution\'s data', () async {
    await ModuleSettingsRepository(db, testSession).setEnabled('students', false);
    const other = AppSession(organizationId: 'org-other', deviceId: 'd', userId: 'u');
    expect(await ModuleSettingsRepository(db, other).loadAll(), isEmpty);
    expect(await AppSettingsRepository(db, other).getValue('anything'), isNull);
  });
}
