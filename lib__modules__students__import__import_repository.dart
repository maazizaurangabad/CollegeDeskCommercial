import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/org_scoped_repository.dart';
import '../../../core/ids/uuid7.dart';
import '../../../platform/academic/academic_repository.dart';
import '../../../platform/data/app_settings_repository.dart';
import '../data/student_repository.dart';
import '../domain/student_models.dart';
import 'import_planner.dart';

/// A finished import, as listed in Settings > Imports.
class ImportBatchInfo {
  const ImportBatchInfo({
    required this.id,
    required this.kind,
    required this.sourceName,
    required this.createdAt,
    required this.added,
    required this.updated,
    required this.skipped,
    required this.undone,
  });

  final String id;
  final String kind;
  final String sourceName;
  final DateTime createdAt;
  final int added;
  final int updated;
  final int skipped;
  final bool undone;
}

class ImportResult {
  const ImportResult({required this.batchId, required this.added, required this.updated, required this.skipped});

  final String batchId;
  final int added;
  final int updated;
  final int skipped;
}

/// A row that stopped the whole import; nothing was saved.
class ImportRowFailure implements Exception {
  const ImportRowFailure(this.rowNumber, this.cause);

  final int rowNumber;
  final Object cause;

  @override
  String toString() => 'Row $rowNumber: $cause';
}

/// A saved column matching, reused for next year's sheet.
class ImportTemplate {
  const ImportTemplate(this.name, this.columns);

  final String name;

  /// normalised header -> field id
  final Map<String, String> columns;

  Map<String, Object?> toJson() => {'name': name, 'columns': columns};

  factory ImportTemplate.fromJson(Map<String, dynamic> json) =>
      ImportTemplate(json['name'] as String, (json['columns'] as Map<String, dynamic>).map((k, v) => MapEntry(k, '$v')));
}

class ImportRepository extends OrgScopedRepository {
  ImportRepository(super.db, super.session, this.students, this.academic, this.settings);

  final StudentRepository students;
  final AcademicRepository academic;
  final AppSettingsRepository settings;

  static const _templatesKey = 'import.templates';

  /// Saves the planned rows in one transaction: either every row goes in, or none.
  Future<ImportResult> commitStudents({
    required ImportPlan plan,
    required ImportOptions options,
    required String sourceName,
    required List<ExtraFieldDefinition> extraFields,
    required String? activeYearId,
  }) {
    return db.transaction(() async {
      // 1. Create classes and divisions the sheet names but the app lacks.
      final createdDivisions = <(String, String), String>{};
      if (plan.missingPlacements.isNotEmpty) {
        if (activeYearId == null) throw StateError('No active academic year');
        for (final (className, divisionName) in plan.missingPlacements) {
          final programs = await academic.listPrograms();
          var programId = programs.where((p) => p.name.toLowerCase() == className.toLowerCase()).firstOrNull?.id;
          programId ??= await academic.addProgram(name: className);
          final existing = (await academic.listDivisions(activeYearId))
              .where((d) => d.programId == programId && d.name.toLowerCase() == divisionName.toLowerCase())
              .firstOrNull;
          createdDivisions[(className, divisionName)] = existing?.id ??
              await academic.addDivision(programId: programId, academicYearId: activeYearId, name: divisionName);
        }
      }

      // 2. Record the batch.
      final ts = now();
      final batchId = Uuid7.generate(ts);
      await db.into(db.importBatches).insert(ImportBatchesCompanion.insert(
            id: batchId,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            kind: 'students',
            sourceName: sourceName,
            settingsJson: Value(jsonEncode({'existing': options.existing.name, 'nameOrder': options.nameOrder.name})),
          ));

      // 3. Each row.
      var added = 0, updated = 0, skipped = 0;
      for (final row in plan.rows) {
        if (row.pendingPlacement != null) row.draft.divisionId = createdDivisions[row.pendingPlacement];
        var action = 'skipped';
        String? studentId = row.existingStudentId;
        try {
          if (row.severity == RowSeverity.error) {
            action = 'skipped';
          } else if (studentId != null) {
            if (options.existing == ExistingPolicy.fillEmpty &&
                await students.fillEmptyFields(studentId, row.draft, extraFields: extraFields)) {
              action = 'updated';
            } else {
              action = 'skipped';
            }
          } else {
            studentId = await students.create(row.draft, extraFields: extraFields);
            action = 'added';
          }
        } catch (e) {
          throw ImportRowFailure(row.rowNumber, e);
        }
        switch (action) {
          case 'added':
            added++;
          case 'updated':
            updated++;
          default:
            skipped++;
        }
        await db.into(db.importRows).insert(ImportRowsCompanion.insert(
              id: Uuid7.generate(ts),
              organizationId: orgId,
              batchId: batchId,
              rowNumber: row.rowNumber,
              serialNo: Value(row.serial),
              studentId: Value(studentId),
              action: action,
              createdAt: ts,
            ));
      }
      await (db.update(db.importBatches)..where((t) => t.id.equals(batchId))).write(ImportBatchesCompanion(
        addedCount: Value(added),
        updatedCount: Value(updated),
        skippedCount: Value(skipped),
      ));
      await changes.record(
        table: 'import_batches',
        rowId: batchId,
        operation: 'insert',
        after: {'kind': 'students', 'source': sourceName, 'added': added, 'updated': updated, 'skipped': skipped},
      );
      return ImportResult(batchId: batchId, added: added, updated: updated, skipped: skipped);
    });
  }

  /// Starts a photo import; each photo is then recorded with [recordPhoto].
  Future<String> startPhotoBatch(String sourceName, String matchKey) async {
    final ts = now();
    final id = Uuid7.generate(ts);
    await db.into(db.importBatches).insert(ImportBatchesCompanion.insert(
          id: id,
          organizationId: orgId,
          createdAt: ts,
          updatedAt: ts,
          createdBy: Value(session.userId),
          updatedBy: Value(session.userId),
          deviceId: session.deviceId,
          kind: 'photos',
          sourceName: sourceName,
          settingsJson: Value(jsonEncode({'matchKey': matchKey})),
        ));
    return id;
  }

  Future<void> recordPhoto(String batchId, int rowNumber, String studentId, String? previous) async {
    await db.into(db.importRows).insert(ImportRowsCompanion.insert(
          id: Uuid7.generate(),
          organizationId: orgId,
          batchId: batchId,
          rowNumber: rowNumber,
          studentId: Value(studentId),
          action: 'photo',
          previousValue: Value(previous),
          createdAt: now(),
        ));
  }

  Future<void> finishPhotoBatch(String batchId, {required int added, required int skipped}) async {
    await (db.update(db.importBatches)..where((t) => t.id.equals(batchId)))
        .write(ImportBatchesCompanion(addedCount: Value(added), skippedCount: Value(skipped)));
    await changes.record(
      table: 'import_batches',
      rowId: batchId,
      operation: 'insert',
      after: {'kind': 'photos', 'added': added, 'skipped': skipped},
    );
  }

  /// Undoes an import: students it added go to the recycle bin, photos it
  /// set are put back as they were. Updates to existing students stay
  /// (they are in the audit log).
  Future<void> undo(String batchId) {
    return db.transaction(() async {
      final batch = await (db.select(db.importBatches)
            ..where((t) => t.id.equals(batchId) & t.organizationId.equals(orgId)))
          .getSingle();
      if (batch.status == 'undone') return;
      final rows = await (db.select(db.importRows)..where((t) => t.batchId.equals(batchId))).get();
      for (final row in rows.reversed) {
        final id = row.studentId;
        if (id == null) continue;
        final alive = await (db.select(db.students)..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (alive == null) continue;
        if (row.action == 'added') await students.moveToRecycleBin(id);
        if (row.action == 'photo') await students.setPhoto(id, row.previousValue);
      }
      await (db.update(db.importBatches)..where((t) => t.id.equals(batchId)))
          .write(ImportBatchesCompanion(status: const Value('undone'), updatedAt: Value(now())));
      await changes.record(
        table: 'import_batches',
        rowId: batchId,
        operation: 'undo',
        before: {'status': 'done'},
        after: {'status': 'undone'},
      );
    });
  }

  Future<List<ImportBatchInfo>> listBatches() async {
    final rows = await (db.select(db.importBatches)
          ..where((t) => t.organizationId.equals(orgId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return [
      for (final r in rows)
        ImportBatchInfo(
          id: r.id,
          kind: r.kind,
          sourceName: r.sourceName,
          createdAt: r.createdAt,
          added: r.addedCount,
          updated: r.updatedCount,
          skipped: r.skippedCount,
          undone: r.status == 'undone',
        ),
    ];
  }

  /// Serial number (from the sheet's Sr. No. column) -> student, for photo matching.
  Future<Map<String, String>> serialMap(String batchId) async {
    final rows = await (db.select(db.importRows)
          ..where((t) => t.batchId.equals(batchId) & t.serialNo.isNotNull() & t.studentId.isNotNull()))
        .get();
    return {for (final r in rows) r.serialNo!: r.studentId!};
  }

  Future<List<ImportTemplate>> templates() async {
    final raw = await settings.getValue(_templatesKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).map((e) => ImportTemplate.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTemplate(ImportTemplate template) async {
    final all = (await templates()).where((t) => t.name.toLowerCase() != template.name.toLowerCase()).toList()
      ..add(template);
    await settings.setValue(_templatesKey, jsonEncode(all.map((t) => t.toJson()).toList()));
  }
}
