import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/org_scoped_repository.dart';
import '../../../core/ids/uuid7.dart';
import '../domain/student_models.dart';

/// Extra student fields an institution defines (blood group, hostel room...).
class FieldDefinitionRepository extends OrgScopedRepository {
  FieldDefinitionRepository(super.db, super.session);

  static const studentEntity = 'student';
  static const fieldTypes = ['text', 'number', 'date', 'choice', 'yesNo'];

  Future<List<ExtraFieldDefinition>> listForStudents() async {
    final rows = await (db.select(db.fieldDefinitions)
          ..where((t) => t.organizationId.equals(orgId) & t.entity.equals(studentEntity) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.displayOrder)]))
        .get();
    return [
      for (final r in rows)
        ExtraFieldDefinition(
          id: r.id,
          key: r.fieldKey,
          label: r.label,
          type: r.fieldType,
          options: (jsonDecode(r.optionsJson) as List<dynamic>).map((e) => '$e').toList(),
          isRequired: r.isRequired,
        ),
    ];
  }

  Future<void> add({required String label, required String type, List<String> options = const [], bool isRequired = false}) {
    return db.transaction(() async {
      final clean = label.trim();
      if (clean.isEmpty) throw ArgumentError('Label required');
      if (!fieldTypes.contains(type)) throw ArgumentError('Unknown field type $type');
      final existing = await listForStudents();
      if (existing.any((f) => f.label.toLowerCase() == clean.toLowerCase())) {
        throw StateError('duplicate');
      }
      final ts = now();
      final id = Uuid7.generate(ts);
      final slug = clean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
      final key = '${slug.isEmpty ? 'field' : slug}_${Uuid7.randomHex(2)}';
      final cleanOptions = options.map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
      await db.into(db.fieldDefinitions).insert(FieldDefinitionsCompanion.insert(
            id: id,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            entity: studentEntity,
            fieldKey: key,
            label: clean,
            fieldType: type,
            optionsJson: Value(jsonEncode(cleanOptions)),
            isRequired: Value(isRequired),
            displayOrder: Value((existing.length + 1) * 10),
          ));
      await changes.record(
        table: 'field_definitions',
        rowId: id,
        operation: 'insert',
        after: {'label': clean, 'type': type, 'options': cleanOptions, 'required': isRequired},
      );
    });
  }

  /// Hides the field. Values already saved on students are kept.
  Future<void> remove(String id) {
    return db.transaction(() async {
      await (db.update(db.fieldDefinitions)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .write(FieldDefinitionsCompanion(deletedAt: Value(now()), updatedAt: Value(now())));
      await changes.record(table: 'field_definitions', rowId: id, operation: 'delete', after: {'deleted': true});
    });
  }
}
