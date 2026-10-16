import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/org_scoped_repository.dart';
import '../../../core/ids/uuid7.dart';
import '../../../platform/data/app_settings_repository.dart';
import 'document_models.dart';

/// Documents students submit. One record per student and document type.
/// Files themselves live in the media folder (see DocumentFiles); this
/// keeps which files belong to which document, in page order.
class DocumentRepository extends OrgScopedRepository {
  DocumentRepository(super.db, super.session, this.settings);

  final AppSettingsRepository settings;

  static DateTime? _day(DateTime? d) => d == null ? null : DateTime.utc(d.year, d.month, d.day);

  // ================================================================= types

  Future<List<DocumentType>> types() async => DocumentTypes.decode(await settings.getValue(DocumentTypes.settingKey));

  Future<void> saveTypes(List<DocumentType> types) => settings.setValue(DocumentTypes.settingKey, DocumentTypes.encode(types));

  // ============================================================== records

  StudentDocument _toModel(StudentDocumentRow r) => StudentDocument(
        id: r.id,
        studentId: r.studentId,
        typeKey: r.typeKey,
        status: DocumentStatus.values.where((s) => s.name == r.status).firstOrNull ?? DocumentStatus.received,
        number: r.number,
        issuedOn: r.issuedOn,
        isOriginal: r.isOriginal,
        returnedOn: r.returnedOn,
        verified: r.verified,
        note: r.note,
        files: [
          for (final f in (() {
            try {
              return jsonDecode(r.filesJson) as List<dynamic>;
            } catch (_) {
              return const <dynamic>[];
            }
          })())
            '$f',
        ],
        updatedAt: r.updatedAt,
      );

  Future<List<StudentDocument>> forStudent(String studentId) async {
    final rows = await (db.select(db.studentDocuments)
          ..where((t) => t.organizationId.equals(orgId) & t.studentId.equals(studentId) & t.deletedAt.isNull()))
        .get();
    return rows.map(_toModel).toList();
  }

  /// Every document of the given students (for the pending-documents report).
  Future<Map<String, List<StudentDocument>>> forStudents(Iterable<String> studentIds) async {
    final ids = studentIds.toSet();
    if (ids.isEmpty) return const {};
    final rows = await (db.select(db.studentDocuments)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.studentId.isIn(ids)))
        .get();
    final out = <String, List<StudentDocument>>{};
    for (final r in rows) {
      (out[r.studentId] ??= []).add(_toModel(r));
    }
    return out;
  }

  /// Each student's category (OBC, SC...), for "only reserved" document rules.
  Future<Map<String, String?>> categoriesOf(Iterable<String> studentIds) async {
    final ids = studentIds.toSet();
    if (ids.isEmpty) return const {};
    final rows =
        await (db.select(db.students)..where((t) => t.organizationId.equals(orgId) & t.id.isIn(ids))).get();
    return {for (final r in rows) r.id: r.category};
  }

  /// Students who have not given every required document, with the missing
  /// ones in the institution's order. [students] are (id, programId) pairs;
  /// a student with nothing missing is left out.
  Future<Map<String, List<DocumentType>>> pendingFor(List<({String studentId, String? programId})> students) async {
    if (students.isEmpty) return const {};
    final ids = students.map((s) => s.studentId);
    final allTypes = await types();
    final docs = await forStudents(ids);
    final categories = await categoriesOf(ids);
    final out = <String, List<DocumentType>>{};
    for (final s in students) {
      final missing = [
        for (final line in documentChecklist(
          allTypes,
          docs[s.studentId] ?? const [],
          programId: s.programId,
          category: categories[s.studentId],
        ))
          if (isMissing(line)) line.type,
      ];
      if (missing.isNotEmpty) out[s.studentId] = missing;
    }
    return out;
  }

  /// Saves a document: creates it the first time, updates it after.
  /// Returns its id.
  Future<String> save(StudentDocument d) {
    return db.transaction(() async {
      final ts = now();
      final existing = await (db.select(db.studentDocuments)
            ..where((t) =>
                t.organizationId.equals(orgId) &
                t.deletedAt.isNull() &
                (d.id != null ? t.id.equals(d.id!) : (t.studentId.equals(d.studentId) & t.typeKey.equals(d.typeKey)))))
          .getSingleOrNull();
      final after = <String, Object?>{
        'student_id': d.studentId,
        'type': d.typeKey,
        'status': d.status.name,
        'number': d.number,
        'issued_on': _day(d.issuedOn)?.toIso8601String(),
        'original': d.isOriginal,
        'returned_on': _day(d.returnedOn)?.toIso8601String(),
        'verified': d.verified,
        'files': d.files.length,
      };
      if (existing == null) {
        final id = Uuid7.generate(ts);
        await db.into(db.studentDocuments).insert(StudentDocumentsCompanion.insert(
              id: id,
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              studentId: d.studentId,
              typeKey: d.typeKey,
              status: Value(d.status.name),
              number: Value(_opt(d.number)),
              issuedOn: Value(_day(d.issuedOn)),
              isOriginal: Value(d.isOriginal),
              returnedOn: Value(_day(d.returnedOn)),
              verified: Value(d.verified),
              note: Value(_opt(d.note)),
              filesJson: Value(jsonEncode(d.files)),
            ));
        await changes.record(table: 'student_documents', rowId: id, operation: 'insert', after: after);
        return id;
      }
      await (db.update(db.studentDocuments)..where((t) => t.id.equals(existing.id))).write(StudentDocumentsCompanion(
        status: Value(d.status.name),
        number: Value(_opt(d.number)),
        issuedOn: Value(_day(d.issuedOn)),
        isOriginal: Value(d.isOriginal),
        returnedOn: Value(_day(d.returnedOn)),
        verified: Value(d.verified),
        note: Value(_opt(d.note)),
        filesJson: Value(jsonEncode(d.files)),
        updatedAt: Value(ts),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(existing.rowVersion + 1),
      ));
      await changes.record(
        table: 'student_documents',
        rowId: existing.id,
        operation: 'update',
        before: {'status': existing.status, 'files': existing.filesJson},
        after: after,
      );
      return existing.id;
    });
  }

  /// Removes the record (to the recycle bin; its files stay on disk).
  Future<void> remove(String id) {
    return db.transaction(() async {
      final ts = now();
      await (db.update(db.studentDocuments)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .write(StudentDocumentsCompanion(deletedAt: Value(ts), updatedAt: Value(ts), updatedBy: Value(session.userId)));
      await changes.record(table: 'student_documents', rowId: id, operation: 'delete', after: {'deleted': true});
    });
  }

  static String? _opt(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}
