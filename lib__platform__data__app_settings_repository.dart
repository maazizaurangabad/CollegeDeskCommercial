import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/database/org_scoped_repository.dart';
import '../../core/ids/uuid7.dart';

/// Simple key/value preferences for one institution (theme and similar).
class AppSettingsRepository extends OrgScopedRepository {
  AppSettingsRepository(super.db, super.session);

  static const _table = 'app_settings';

  Future<String?> getValue(String key) async {
    final row = await (db.select(db.appSettings)
          ..where((t) => t.organizationId.equals(orgId) & t.settingKey.equals(key) & t.deletedAt.isNull()))
        .getSingleOrNull();
    return row?.settingValue;
  }

  Future<void> setValue(String key, String value) {
    return db.transaction(() async {
      final existing = await (db.select(db.appSettings)
            ..where((t) => t.organizationId.equals(orgId) & t.settingKey.equals(key)))
          .getSingleOrNull();
      final ts = now();
      if (existing == null) {
        final id = Uuid7.generate(ts);
        await db.into(db.appSettings).insert(AppSettingsCompanion.insert(
              id: id,
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              settingKey: key,
              settingValue: value,
            ));
        await changes.record(table: _table, rowId: id, operation: 'insert', after: {'key': key, 'value': value});
        return;
      }
      if (existing.settingValue == value && existing.deletedAt == null) return;
      await (db.update(db.appSettings)..where((t) => t.id.equals(existing.id))).write(
        AppSettingsCompanion(
          settingValue: Value(value),
          updatedAt: Value(ts),
          updatedBy: Value(session.userId),
          rowVersion: Value(existing.rowVersion + 1),
          deviceId: Value(session.deviceId),
          deletedAt: const Value(null),
        ),
      );
      await changes.record(
        table: _table,
        rowId: existing.id,
        operation: 'update',
        before: {'key': key, 'value': existing.settingValue},
        after: {'key': key, 'value': value},
      );
    });
  }
}
