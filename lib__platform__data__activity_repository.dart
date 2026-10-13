import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/org_scoped_repository.dart';

/// One line of "recent activity", read from the audit log.
class ActivityItem {
  const ActivityItem({required this.entity, required this.action, required this.at, required this.details});

  final String entity;
  final String action;
  final DateTime at;

  /// The audit entry's changes: field -> {old, new}.
  final Map<String, dynamic> details;

  /// The new value of a field, if it was recorded.
  Object? value(String field) => (details[field] as Map<String, dynamic>?)?['new'];
}

/// Reads the audit log for the dashboard. Shows only meaningful events.
class ActivityRepository extends OrgScopedRepository {
  ActivityRepository(super.db, super.session);

  static const _shown = {'students', 'attendance_sessions', 'import_batches', 'academic_years'};

  Future<List<ActivityItem>> recent({int limit = 8}) async {
    final rows = await (db.select(db.auditEntries)
          ..where((t) => t.organizationId.equals(orgId) & t.entity.isIn(_shown))
          ..orderBy([(t) => OrderingTerm.desc(t.at)])
          ..limit(60))
        .get();
    final out = <ActivityItem>[];
    for (final r in rows) {
      // Skip small field edits; keep additions, saves, imports and deletions.
      final interesting = r.action == 'insert' ||
          r.action == 'delete' ||
          r.action == 'restore' ||
          r.entity == 'attendance_sessions' ||
          (r.entity == 'students' && r.changes.contains('"status"'));
      if (!interesting) continue;
      Map<String, dynamic> details;
      try {
        details = jsonDecode(r.changes) as Map<String, dynamic>;
      } catch (_) {
        details = {};
      }
      out.add(ActivityItem(entity: r.entity, action: r.action, at: r.at, details: details));
      if (out.length >= limit) break;
    }
    return out;
  }
}
