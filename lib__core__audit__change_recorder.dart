import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../ids/uuid7.dart';
import '../session/app_session.dart';

/// Writes one audit entry and one outbox entry for every change.
/// Always called inside the same transaction as the change itself.
class ChangeRecorder {
  ChangeRecorder(this._db, this._session);

  final AppDatabase _db;
  final AppSession _session;

  Future<void> record({
    required String table,
    required String rowId,
    required String operation,
    Map<String, Object?>? before,
    required Map<String, Object?> after,
  }) async {
    final now = DateTime.now().toUtc();
    final changed = <String, Object?>{};
    for (final key in {...?before?.keys, ...after.keys}) {
      final oldValue = before?[key];
      final newValue = after[key];
      if (oldValue != newValue) changed[key] = {'old': oldValue, 'new': newValue};
    }
    await _db.into(_db.auditEntries).insert(AuditEntriesCompanion.insert(
          id: Uuid7.generate(now),
          organizationId: _session.organizationId,
          entity: table,
          entityId: rowId,
          action: operation,
          changes: jsonEncode(changed),
          userId: Value(_session.userId),
          deviceId: _session.deviceId,
          at: now,
        ));
    await _db.into(_db.outboxEntries).insert(OutboxEntriesCompanion.insert(
          id: Uuid7.generate(now),
          organizationId: _session.organizationId,
          targetTable: table,
          rowId: rowId,
          operation: operation,
          payload: jsonEncode(after),
          createdAt: now,
        ));
  }
}
