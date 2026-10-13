import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/database/org_scoped_repository.dart';
import '../../core/ids/uuid7.dart';

/// Which modules an institution has switched on.
class ModuleSettingsRepository extends OrgScopedRepository {
  ModuleSettingsRepository(super.db, super.session);

  static const _table = 'module_settings';

  /// moduleId -> enabled, for this institution only.
  Future<Map<String, bool>> loadAll() async {
    final rows = await (db.select(db.moduleSettings)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull()))
        .get();
    return {for (final r in rows) r.moduleId: r.enabled};
  }

  Future<void> setEnabled(String moduleId, bool enabled) {
    return db.transaction(() async {
      final existing = await (db.select(db.moduleSettings)
            ..where((t) => t.organizationId.equals(orgId) & t.moduleId.equals(moduleId)))
          .getSingleOrNull();
      final ts = now();
      if (existing == null) {
        final id = Uuid7.generate(ts);
        await db.into(db.moduleSettings).insert(ModuleSettingsCompanion.insert(
              id: id,
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              moduleId: moduleId,
              enabled: enabled,
            ));
        await changes.record(
          table: _table,
          rowId: id,
          operation: 'insert',
          after: {'module_id': moduleId, 'enabled': enabled},
        );
        return;
      }
      if (existing.enabled == enabled && existing.deletedAt == null) return;
      await (db.update(db.moduleSettings)..where((t) => t.id.equals(existing.id))).write(
        ModuleSettingsCompanion(
          enabled: Value(enabled),
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
        before: {'module_id': moduleId, 'enabled': existing.enabled},
        after: {'module_id': moduleId, 'enabled': enabled},
      );
    });
  }
}
