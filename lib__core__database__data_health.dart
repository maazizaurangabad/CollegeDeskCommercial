import 'package:drift/drift.dart';

import 'app_database.dart';

enum HealthCheck {
  integrity,
  orphanEnrollments,
  duplicateRolls,
  multipleActiveEnrollments,
  duplicateIdentifiers,
  unplacedActiveStudents,
}

class HealthFinding {
  const HealthFinding(this.check, this.count, [this.detail]);

  final HealthCheck check;

  /// 0 means the check passed.
  final int count;
  final String? detail;

  bool get ok => count == 0;
}

/// Read-only checks of one institution's data. Changes nothing.
abstract final class DataHealth {
  static Future<List<HealthFinding>> run(AppDatabase db, String orgId, {String? activeYearId}) async {
    Future<int> count(String sql, [List<String> args = const []]) async {
      final row = await db
          .customSelect(sql, variables: [for (final a in args) Variable.withString(a)])
          .getSingle();
      return row.data.values.first as int;
    }

    final check = await db.customSelect('PRAGMA quick_check').get();
    final integrity = check.map((r) => '${r.data.values.first}').where((v) => v != 'ok').toList();

    final orphans = await count('''
      SELECT count(*) FROM enrollments e
      WHERE e.organization_id = ? AND e.deleted_at IS NULL AND (
        NOT EXISTS (SELECT 1 FROM students s WHERE s.id = e.student_id)
        OR NOT EXISTS (SELECT 1 FROM divisions d WHERE d.id = e.division_id))''', [orgId]);

    final duplicateRolls = await count('''
      SELECT count(*) FROM (
        SELECT e.division_id, e.roll_number FROM enrollments e
        JOIN students s ON s.id = e.student_id AND s.deleted_at IS NULL
        WHERE e.organization_id = ? AND e.status = 'active' AND e.deleted_at IS NULL AND e.roll_number IS NOT NULL
        GROUP BY e.division_id, e.roll_number HAVING count(*) > 1)''', [orgId]);

    final multipleActive = await count('''
      SELECT count(*) FROM (
        SELECT e.student_id FROM enrollments e
        WHERE e.organization_id = ? AND e.status = 'active' AND e.deleted_at IS NULL
        GROUP BY e.student_id HAVING count(*) > 1)''', [orgId]);

    final duplicateIds = await count('''
      SELECT count(*) FROM (
        SELECT i.id_type, lower(i.id_value) FROM student_identifiers i
        JOIN students s ON s.id = i.student_id AND s.deleted_at IS NULL
        WHERE i.organization_id = ? AND i.deleted_at IS NULL AND i.id_type <> 'aadhaar'
        GROUP BY i.id_type, lower(i.id_value) HAVING count(*) > 1)''', [orgId]);

    final unplaced = activeYearId == null
        ? 0
        : await count('''
      SELECT count(*) FROM students s
      WHERE s.organization_id = ? AND s.deleted_at IS NULL AND s.status = 'active'
        AND NOT EXISTS (SELECT 1 FROM enrollments e WHERE e.student_id = s.id AND e.status = 'active'
                        AND e.academic_year_id = ? AND e.deleted_at IS NULL)''', [orgId, activeYearId]);

    return [
      HealthFinding(HealthCheck.integrity, integrity.length, integrity.isEmpty ? null : integrity.take(3).join('; ')),
      HealthFinding(HealthCheck.orphanEnrollments, orphans),
      HealthFinding(HealthCheck.duplicateRolls, duplicateRolls),
      HealthFinding(HealthCheck.multipleActiveEnrollments, multipleActive),
      HealthFinding(HealthCheck.duplicateIdentifiers, duplicateIds),
      HealthFinding(HealthCheck.unplacedActiveStudents, unplaced),
    ];
  }
}
