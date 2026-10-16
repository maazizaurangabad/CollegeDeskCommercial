import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/org_scoped_repository.dart';
import '../../../core/ids/uuid7.dart';
import '../../../platform/academic/academic_repository.dart';
import '../../fees/data/fee_repository.dart';
import '../../results/data/result_repository.dart';
import '../../results/domain/result_models.dart';
import '../data/student_repository.dart';
import '../domain/student_models.dart';
import 'promotion_models.dart';

/// Year-end promotion: every student of the closing year moves up, repeats
/// or leaves, in one step that can be undone. Last year's records (class,
/// attendance, results, fees) stay with last year.
class PromotionRepository extends OrgScopedRepository {
  PromotionRepository(super.db, super.session, this.students, this.academic, this.results, this.fees);

  final StudentRepository students;
  final AcademicRepository academic;
  final ResultRepository results;
  final FeeRepository fees;

  static const batchKind = 'promotion';

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// Everyone still in a class of [fromYearId], with the suggested action.
  /// Students already placed in [toYearId] are left out (e.g. promoted
  /// before), as are students who left.
  Future<List<PromotionCandidate>> candidates({
    required String fromYearId,
    required String toYearId,
    bool promoteAtkt = true,
  }) async {
    final divisions = await academic.listDivisions(fromYearId);
    final programs = {for (final p in await academic.listPrograms()) p.id: p};
    final enrollments = await (db.select(db.enrollments)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.academicYearId.equals(fromYearId) &
              t.deletedAt.isNull() &
              t.status.equals(EnrollmentStatus.active.name)))
        .get();
    if (enrollments.isEmpty) return [];
    final alreadyNext = {
      for (final e in await (db.select(db.enrollments)
            ..where((t) => t.organizationId.equals(orgId) & t.academicYearId.equals(toYearId) & t.deletedAt.isNull()))
          .get())
        e.studentId,
    };
    final ids = enrollments.map((e) => e.studentId).toSet();
    final names = await students.namesFor(ids);
    final grs = {
      for (final i in await (db.select(db.studentIdentifiers)
            ..where((t) =>
                t.organizationId.equals(orgId) &
                t.deletedAt.isNull() &
                t.idType.equals(IdentifierType.grNumber.code) &
                t.studentId.isIn(ids)))
          .get())
        i.studentId: i.idValue,
    };
    final active = {
      for (final s in await (db.select(db.students)
            ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.id.isIn(ids)))
          .get())
        if (s.status == StudentStatus.active.name) s.id,
    };

    // Final results, class by class (the same as the result sheet).
    final outcome = <String, ResultStatus>{};
    for (final d in divisions) {
      try {
        final sheet = await results.classResult(divisionId: d.id, programId: d.programId, academicYearId: fromYearId);
        if (sheet.columns.isEmpty || sheet.exams.isEmpty) continue;
        for (final r in sheet.results) {
          outcome[r.studentId] = r.status;
        }
      } catch (_) {
        // No results for this class: everyone is "no result".
      }
    }

    final byId = {for (final d in divisions) d.id: d};
    final list = <PromotionCandidate>[];
    for (final e in enrollments) {
      final d = byId[e.divisionId];
      if (d == null || alreadyNext.contains(e.studentId) || !active.contains(e.studentId)) continue;
      final next = programs[d.programId]?.nextProgramId;
      final result = outcome[e.studentId];
      list.add(PromotionCandidate(
        studentId: e.studentId,
        name: names[e.studentId]?.fullName ?? '',
        grNumber: grs[e.studentId],
        fromDivisionId: d.id,
        fromProgramId: d.programId,
        divisionName: d.name,
        roll: e.rollNumber,
        result: result,
        nextProgramId: next,
        action: suggestedAction(result: result, hasNext: next != null, promoteAtkt: promoteAtkt),
      ));
    }
    list.sort((a, b) {
      final c = a.fromDivisionId.compareTo(b.fromDivisionId);
      return c != 0 ? c : (a.roll ?? 1 << 30).compareTo(b.roll ?? 1 << 30);
    });
    return list;
  }

  /// Saves the promotion in one transaction. Missing divisions of next
  /// year are created with the same names. Optionally copies fee
  /// structures and makes next year the active year afterwards.
  Future<PromotionResult> commit({
    required String fromYearId,
    required String toYearId,
    required List<PromotionCandidate> candidates,
    RollOrder rollOrder = RollOrder.byName,
    required String leaveReason,
    bool copyFees = true,
    bool makeActive = false,
  }) async {
    if (fromYearId == toYearId) throw ArgumentError('Choose a different year to promote into');
    final fromYear = await (db.select(db.academicYears)..where((t) => t.id.equals(fromYearId))).getSingle();
    final toYear = await (db.select(db.academicYears)..where((t) => t.id.equals(toYearId))).getSingle();
    final result = await db.transaction(() async {
      final ts = now();
      // The old class ends the day after the year ends (the register counts
      // the student until the last day).
      final endOld = _day(fromYear.endDate).add(const Duration(days: 1));
      final leftOn = _day(fromYear.endDate);

      // Divisions of next year: (program, lower-case name) -> id.
      final targets = <(String, String), String>{
        for (final d in await academic.listDivisions(toYearId)) (d.programId, d.name.toLowerCase()): d.id,
      };
      Future<String> divisionFor(String programId, String name) async {
        final key = (programId, name.toLowerCase());
        return targets[key] ??= await academic.addDivision(programId: programId, academicYearId: toYearId, name: name);
      }

      // Who goes where, then roll numbers per new class.
      final moving = candidates.where((c) => c.action == PromotionAction.promote || c.action == PromotionAction.repeat).toList();
      final targetOf = <String, String>{};
      for (final c in moving) {
        final program = c.toProgramId;
        if (program == null) {
          c.action = PromotionAction.skip; // no next class set: decide later
          continue;
        }
        targetOf[c.studentId] = await divisionFor(program, c.divisionName);
      }
      final rolls = <String, int>{};
      for (final divisionId in targetOf.values.toSet()) {
        final taken = {
          for (final e in await (db.select(db.enrollments)
                ..where((t) =>
                    t.organizationId.equals(orgId) &
                    t.divisionId.equals(divisionId) &
                    t.deletedAt.isNull() &
                    t.status.equals(EnrollmentStatus.active.name)))
              .get())
            if (e.rollNumber != null) e.rollNumber!,
        };
        rolls.addAll(assignRolls(
          [for (final c in moving) if (targetOf[c.studentId] == divisionId) c],
          order: rollOrder,
          taken: taken,
        ));
      }

      final batchId = Uuid7.generate(ts);
      await db.into(db.importBatches).insert(ImportBatchesCompanion.insert(
            id: batchId,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            kind: batchKind,
            sourceName: '${fromYear.label} → ${toYear.label}',
            settingsJson: Value(jsonEncode({'from': fromYearId, 'to': toYearId, 'rollOrder': rollOrder.name})),
          ));

      var promoted = 0, repeated = 0, left = 0, skipped = 0, n = 0;
      for (final c in candidates) {
        n++;
        if (c.action == PromotionAction.skip) {
          skipped++;
          continue;
        }
        final old = await (db.select(db.enrollments)
              ..where((t) =>
                  t.organizationId.equals(orgId) &
                  t.studentId.equals(c.studentId) &
                  t.academicYearId.equals(fromYearId) &
                  t.deletedAt.isNull() &
                  t.status.equals(EnrollmentStatus.active.name)))
            .getSingleOrNull();
        if (old == null) {
          skipped++;
          continue;
        }
        final student = await (db.select(db.students)..where((t) => t.id.equals(c.studentId))).getSingle();
        final endStatus = switch (c.action) {
          PromotionAction.promote => EnrollmentStatus.promoted,
          PromotionAction.repeat => EnrollmentStatus.detained,
          _ => EnrollmentStatus.graduated,
        };
        await (db.update(db.enrollments)..where((t) => t.id.equals(old.id))).write(EnrollmentsCompanion(
          status: Value(endStatus.name),
          endDate: Value(endOld),
          updatedAt: Value(ts),
          updatedBy: Value(session.userId),
          deviceId: Value(session.deviceId),
          rowVersion: Value(old.rowVersion + 1),
        ));
        await changes.record(
          table: 'enrollments',
          rowId: old.id,
          operation: 'update',
          before: {'status': old.status, 'end_date': old.endDate?.toIso8601String()},
          after: {'status': endStatus.name, 'end_date': endOld.toIso8601String(), 'promotion': batchId},
        );

        String? newId;
        if (c.action == PromotionAction.leave) {
          await (db.update(db.students)..where((t) => t.id.equals(c.studentId))).write(StudentsCompanion(
            status: Value(StudentStatus.left.name),
            leavingDate: Value(leftOn),
            leavingReason: Value(leaveReason),
            updatedAt: Value(ts),
            updatedBy: Value(session.userId),
            deviceId: Value(session.deviceId),
            rowVersion: Value(student.rowVersion + 1),
          ));
          await changes.record(
            table: 'students',
            rowId: c.studentId,
            operation: 'update',
            before: {'status': student.status},
            after: {'status': StudentStatus.left.name, 'leaving_reason': leaveReason, 'promotion': batchId},
          );
          left++;
        } else {
          newId = Uuid7.generate(ts);
          final divisionId = targetOf[c.studentId]!;
          final roll = rolls[c.studentId];
          await db.into(db.enrollments).insert(EnrollmentsCompanion.insert(
                id: newId,
                organizationId: orgId,
                createdAt: ts,
                updatedAt: ts,
                createdBy: Value(session.userId),
                updatedBy: Value(session.userId),
                deviceId: session.deviceId,
                studentId: c.studentId,
                academicYearId: toYearId,
                divisionId: divisionId,
                rollNumber: Value(roll),
                startDate: _day(toYear.startDate),
                status: EnrollmentStatus.active.name,
              ));
          await changes.record(
            table: 'enrollments',
            rowId: newId,
            operation: 'insert',
            after: {'student_id': c.studentId, 'division_id': divisionId, 'roll_number': roll, 'promotion': batchId},
          );
          if (c.action == PromotionAction.promote) {
            promoted++;
          } else {
            repeated++;
          }
        }

        await db.into(db.importRows).insert(ImportRowsCompanion.insert(
              id: Uuid7.generate(ts),
              organizationId: orgId,
              batchId: batchId,
              rowNumber: n,
              studentId: Value(c.studentId),
              action: c.action.name,
              previousValue: Value(jsonEncode({
                'oldEnrollment': old.id,
                'oldStatus': old.status,
                'oldEnd': old.endDate?.toIso8601String(),
                'newEnrollment': newId,
                'studentStatus': student.status,
                'leavingDate': student.leavingDate?.toIso8601String(),
                'leavingReason': student.leavingReason,
              })),
              createdAt: ts,
            ));
      }
      await (db.update(db.importBatches)..where((t) => t.id.equals(batchId))).write(ImportBatchesCompanion(
        addedCount: Value(promoted),
        updatedCount: Value(repeated),
        skippedCount: Value(left),
      ));
      await changes.record(
        table: 'import_batches',
        rowId: batchId,
        operation: 'insert',
        after: {'kind': batchKind, 'promoted': promoted, 'repeated': repeated, 'left': left, 'skipped': skipped},
      );
      return PromotionResult(batchId: batchId, promoted: promoted, repeated: repeated, left: left, skipped: skipped);
    });

    // Setup for next year, outside the student changes.
    var feesCopied = 0;
    if (copyFees) feesCopied = await fees.copyStructures(fromYearId: fromYearId, toYearId: toYearId);
    if (makeActive) await academic.setActiveYear(toYearId);
    return PromotionResult(
      batchId: result.batchId,
      promoted: result.promoted,
      repeated: result.repeated,
      left: result.left,
      skipped: result.skipped,
      feesCopied: feesCopied,
    );
  }

  /// Puts every student back where they were before the promotion. Fee
  /// structures copied and the active year are left as they are.
  Future<void> undo(String batchId) {
    return db.transaction(() async {
      final batch = await (db.select(db.importBatches)
            ..where((t) => t.id.equals(batchId) & t.organizationId.equals(orgId) & t.kind.equals(batchKind)))
          .getSingle();
      if (batch.status == 'undone') return;
      final ts = now();
      final rows = await (db.select(db.importRows)..where((t) => t.batchId.equals(batchId))).get();
      for (final row in rows.reversed) {
        final before = jsonDecode(row.previousValue ?? '{}') as Map<String, dynamic>;
        final newId = before['newEnrollment'] as String?;
        if (newId != null) {
          await (db.update(db.enrollments)..where((t) => t.id.equals(newId)))
              .write(EnrollmentsCompanion(deletedAt: Value(ts), updatedAt: Value(ts), updatedBy: Value(session.userId)));
          await changes.record(table: 'enrollments', rowId: newId, operation: 'delete', after: {'undo': batchId});
        }
        final oldId = before['oldEnrollment'] as String?;
        if (oldId != null) {
          final oldEnd = before['oldEnd'] as String?;
          await (db.update(db.enrollments)..where((t) => t.id.equals(oldId))).write(EnrollmentsCompanion(
            status: Value(before['oldStatus'] as String? ?? EnrollmentStatus.active.name),
            endDate: Value(oldEnd == null ? null : DateTime.parse(oldEnd)),
            updatedAt: Value(ts),
            updatedBy: Value(session.userId),
          ));
          await changes.record(table: 'enrollments', rowId: oldId, operation: 'update', after: {'undo': batchId});
        }
        final id = row.studentId;
        if (row.action == PromotionAction.leave.name && id != null) {
          final leavingDate = before['leavingDate'] as String?;
          await (db.update(db.students)..where((t) => t.id.equals(id))).write(StudentsCompanion(
            status: Value(before['studentStatus'] as String? ?? StudentStatus.active.name),
            leavingDate: Value(leavingDate == null ? null : DateTime.parse(leavingDate)),
            leavingReason: Value(before['leavingReason'] as String?),
            updatedAt: Value(ts),
            updatedBy: Value(session.userId),
          ));
          await changes.record(table: 'students', rowId: id, operation: 'update', after: {'undo': batchId});
        }
      }
      await (db.update(db.importBatches)..where((t) => t.id.equals(batchId)))
          .write(ImportBatchesCompanion(status: const Value('undone'), updatedAt: Value(ts)));
      await changes.record(
        table: 'import_batches',
        rowId: batchId,
        operation: 'undo',
        before: {'status': 'done'},
        after: {'status': 'undone'},
      );
    });
  }

  Future<List<PromotionBatch>> history() async {
    final rows = await (db.select(db.importBatches)
          ..where((t) => t.organizationId.equals(orgId) & t.kind.equals(batchKind))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return [
      for (final r in rows)
        PromotionBatch(
          id: r.id,
          label: r.sourceName,
          createdAt: r.createdAt,
          promoted: r.addedCount,
          repeated: r.updatedCount,
          left: r.skippedCount,
          undone: r.status == 'undone',
        ),
    ];
  }
}
