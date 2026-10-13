import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/database/org_scoped_repository.dart';
import '../../core/ids/uuid7.dart';
import 'academic_models.dart';

/// Academic years, classes (programs) and divisions for one institution.
/// All rules are checked here, not only on screen.
class AcademicRepository extends OrgScopedRepository {
  AcademicRepository(super.db, super.session);

  // ---------------------------------------------------------------- reading

  Future<AcademicSnapshot> loadSnapshot() async {
    final years = await listYears();
    AcademicYear? active;
    for (final y in years) {
      if (y.isActive) active = y;
    }
    return AcademicSnapshot(
      years: years,
      programs: await listPrograms(),
      divisions: active == null ? const [] : await listDivisions(active.id),
    );
  }

  Future<List<AcademicYear>> listYears() async {
    final rows = await (db.select(db.academicYears)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
        .get();
    return rows.map(_year).toList();
  }

  Future<List<Program>> listPrograms() async {
    final rows = await (db.select(db.programs)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.levelOrder)]))
        .get();
    return rows.map(_program).toList();
  }

  Future<List<Division>> listDivisions(String academicYearId) async {
    final rows = await (db.select(db.divisions)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.academicYearId.equals(academicYearId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.displayOrder)]))
        .get();
    return rows.map(_division).toList();
  }

  /// "11th Science A" for every division in every year, including deleted ones,
  /// so old class history always shows a name.
  Future<Map<String, String>> divisionLabels() async {
    final programs = await (db.select(db.programs)..where((t) => t.organizationId.equals(orgId))).get();
    final names = {for (final p in programs) p.id: p.name};
    final divisions = await (db.select(db.divisions)..where((t) => t.organizationId.equals(orgId))).get();
    return {for (final d in divisions) d.id: '${names[d.programId] ?? ''} ${d.name}'.trim()};
  }

  // ---------------------------------------------------------- academic years

  Future<String> addYear({
    required String label,
    required DateTime startDate,
    required DateTime endDate,
    bool makeActive = false,
  }) {
    return db.transaction(() async {
      final clean = label.trim();
      if (clean.isEmpty) throw const AcademicValidationException(AcademicIssue.emptyName);
      if (!endDate.isAfter(startDate)) throw const AcademicValidationException(AcademicIssue.endBeforeStart);
      final existing = await listYears();
      if (existing.any((y) => y.label.toLowerCase() == clean.toLowerCase())) {
        throw const AcademicValidationException(AcademicIssue.duplicateYear);
      }
      final ts = now();
      final id = Uuid7.generate(ts);
      await db.into(db.academicYears).insert(AcademicYearsCompanion.insert(
            id: id,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            label: clean,
            startDate: _dateOnly(startDate),
            endDate: _dateOnly(endDate),
            status: AcademicYearStatus.inactive.name,
          ));
      await changes.record(
        table: 'academic_years',
        rowId: id,
        operation: 'insert',
        after: {'label': clean, 'start_date': _iso(startDate), 'end_date': _iso(endDate), 'status': 'inactive'},
      );
      if (makeActive) await setActiveYear(id);
      return id;
    });
  }

  /// Makes [yearId] the one active year. The previously active year
  /// becomes inactive (still viewable). Keeps the institution's
  /// displayed year in step.
  Future<void> setActiveYear(String yearId) {
    return db.transaction(() async {
      final target = await _yearRow(yearId);
      if (target.status == AcademicYearStatus.closed.name) {
        throw const AcademicValidationException(AcademicIssue.yearIsClosed);
      }
      final current = await (db.select(db.academicYears)
            ..where((t) =>
                t.organizationId.equals(orgId) &
                t.status.equals(AcademicYearStatus.active.name) &
                t.deletedAt.isNull()))
          .get();
      for (final row in current) {
        if (row.id != yearId) await _setYearStatus(row, AcademicYearStatus.inactive);
      }
      if (target.status != AcademicYearStatus.active.name) {
        await _setYearStatus(target, AcademicYearStatus.active);
      }
      final org = await (db.select(db.organizations)..where((t) => t.id.equals(orgId))).getSingleOrNull();
      if (org == null || org.activeAcademicYear == target.label) return;
      final ts = now();
      await (db.update(db.organizations)..where((t) => t.id.equals(orgId))).write(OrganizationsCompanion(
        activeAcademicYear: Value(target.label),
        updatedAt: Value(ts),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(org.rowVersion + 1),
      ));
      await changes.record(
        table: 'organizations',
        rowId: orgId,
        operation: 'update',
        before: {'active_academic_year': org.activeAcademicYear},
        after: {'active_academic_year': target.label},
      );
    });
  }

  /// A closed year becomes read-only history. The active year cannot be closed.
  Future<void> closeYear(String yearId) {
    return db.transaction(() async {
      final row = await _yearRow(yearId);
      if (row.status == AcademicYearStatus.active.name) {
        throw const AcademicValidationException(AcademicIssue.cannotCloseActiveYear);
      }
      if (row.status == AcademicYearStatus.closed.name) return;
      await _setYearStatus(row, AcademicYearStatus.closed);
    });
  }

  // --------------------------------------------------------------- programs

  Future<String> addProgram({required String name, String? stream}) {
    return db.transaction(() async {
      final clean = _requireName(name);
      final programs = await listPrograms();
      if (programs.any((p) => p.name.toLowerCase() == clean.toLowerCase())) {
        throw const AcademicValidationException(AcademicIssue.duplicateProgram);
      }
      final order = programs.isEmpty ? 10 : programs.last.levelOrder + 10;
      final ts = now();
      final id = Uuid7.generate(ts);
      final cleanStream = (stream == null || stream.trim().isEmpty) ? null : stream.trim();
      await db.into(db.programs).insert(ProgramsCompanion.insert(
            id: id,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            name: clean,
            stream: Value(cleanStream),
            levelOrder: order,
          ));
      await changes.record(
        table: 'programs',
        rowId: id,
        operation: 'insert',
        after: {'name': clean, 'stream': cleanStream, 'level_order': order},
      );
      return id;
    });
  }

  Future<void> renameProgram(String programId, String newName) {
    return db.transaction(() async {
      final clean = _requireName(newName);
      final row = await _programRow(programId);
      if (row.name == clean) return;
      final others = await listPrograms();
      if (others.any((p) => p.id != programId && p.name.toLowerCase() == clean.toLowerCase())) {
        throw const AcademicValidationException(AcademicIssue.duplicateProgram);
      }
      await _writeProgram(row, ProgramsCompanion(name: Value(clean)), {'name': row.name}, {'name': clean});
    });
  }

  Future<void> setNextProgram(String programId, String? nextProgramId) {
    return db.transaction(() async {
      final row = await _programRow(programId);
      if (row.nextProgramId == nextProgramId) return;
      await _writeProgram(
        row,
        ProgramsCompanion(nextProgramId: Value(nextProgramId)),
        {'next_program_id': row.nextProgramId},
        {'next_program_id': nextProgramId},
      );
    });
  }

  /// Swaps this class with its neighbour in the list.
  Future<void> moveProgram(String programId, {required bool up}) {
    return db.transaction(() async {
      final programs = await listPrograms();
      final index = programs.indexWhere((p) => p.id == programId);
      if (index < 0) throw const AcademicValidationException(AcademicIssue.notFound);
      final otherIndex = up ? index - 1 : index + 1;
      if (otherIndex < 0 || otherIndex >= programs.length) return;
      final a = await _programRow(programs[index].id);
      final b = await _programRow(programs[otherIndex].id);
      await _writeProgram(a, ProgramsCompanion(levelOrder: Value(b.levelOrder)), {'level_order': a.levelOrder},
          {'level_order': b.levelOrder});
      await _writeProgram(b, ProgramsCompanion(levelOrder: Value(a.levelOrder)), {'level_order': b.levelOrder},
          {'level_order': a.levelOrder});
    });
  }

  /// Refused while the class still has divisions in any year.
  Future<void> deleteProgram(String programId) {
    return db.transaction(() async {
      final row = await _programRow(programId);
      final divisions = await (db.select(db.divisions)
            ..where((t) => t.organizationId.equals(orgId) & t.programId.equals(programId) & t.deletedAt.isNull()))
          .get();
      if (divisions.isNotEmpty) throw const AcademicValidationException(AcademicIssue.programHasDivisions);
      await _writeProgram(row, ProgramsCompanion(deletedAt: Value(now())), {'deleted': false}, {'deleted': true},
          operation: 'delete');
    });
  }

  // -------------------------------------------------------------- divisions

  Future<String> addDivision({
    required String programId,
    required String academicYearId,
    required String name,
    int? capacity,
  }) {
    return db.transaction(() async {
      final clean = _requireName(name);
      await _programRow(programId);
      final year = await _yearRow(academicYearId);
      if (year.status == AcademicYearStatus.closed.name) {
        throw const AcademicValidationException(AcademicIssue.yearIsClosed);
      }
      final siblings = (await listDivisions(academicYearId)).where((d) => d.programId == programId).toList();
      if (siblings.any((d) => d.name.toLowerCase() == clean.toLowerCase())) {
        throw const AcademicValidationException(AcademicIssue.duplicateDivision);
      }
      final order = siblings.isEmpty ? 10 : siblings.map((d) => d.displayOrder).reduce((a, b) => a > b ? a : b) + 10;
      final ts = now();
      final id = Uuid7.generate(ts);
      await db.into(db.divisions).insert(DivisionsCompanion.insert(
            id: id,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            programId: programId,
            academicYearId: academicYearId,
            name: clean,
            capacity: Value(capacity),
            displayOrder: Value(order),
          ));
      await changes.record(
        table: 'divisions',
        rowId: id,
        operation: 'insert',
        after: {'program_id': programId, 'academic_year_id': academicYearId, 'name': clean, 'capacity': capacity},
      );
      return id;
    });
  }

  Future<void> renameDivision(String divisionId, String newName) {
    return db.transaction(() async {
      final clean = _requireName(newName);
      final row = await _divisionRow(divisionId);
      if (row.name == clean) return;
      final siblings = (await listDivisions(row.academicYearId)).where((d) => d.programId == row.programId);
      if (siblings.any((d) => d.id != divisionId && d.name.toLowerCase() == clean.toLowerCase())) {
        throw const AcademicValidationException(AcademicIssue.duplicateDivision);
      }
      await _writeDivision(row, DivisionsCompanion(name: Value(clean)), {'name': row.name}, {'name': clean});
    });
  }

  /// Soft delete. Refused while students are actively placed in it.
  Future<void> deleteDivision(String divisionId) {
    return db.transaction(() async {
      final row = await _divisionRow(divisionId);
      final placed = await (db.select(db.enrollments)
            ..where((t) =>
                t.organizationId.equals(orgId) &
                t.divisionId.equals(divisionId) &
                t.status.equals('active') &
                t.deletedAt.isNull()))
          .get();
      for (final e in placed) {
        final student = await (db.select(db.students)
              ..where((t) => t.id.equals(e.studentId) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (student != null) throw const AcademicValidationException(AcademicIssue.divisionHasStudents);
      }
      await _writeDivision(row, DivisionsCompanion(deletedAt: Value(now())), {'deleted': false}, {'deleted': true},
          operation: 'delete');
    });
  }

  // ---------------------------------------------------------------- helpers

  String _requireName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) throw const AcademicValidationException(AcademicIssue.emptyName);
    return clean;
  }

  Future<AcademicYearRow> _yearRow(String id) async {
    final row = await (db.select(db.academicYears)
          ..where((t) => t.id.equals(id) & t.organizationId.equals(orgId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) throw const AcademicValidationException(AcademicIssue.notFound);
    return row;
  }

  Future<ProgramRow> _programRow(String id) async {
    final row = await (db.select(db.programs)
          ..where((t) => t.id.equals(id) & t.organizationId.equals(orgId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) throw const AcademicValidationException(AcademicIssue.notFound);
    return row;
  }

  Future<DivisionRow> _divisionRow(String id) async {
    final row = await (db.select(db.divisions)
          ..where((t) => t.id.equals(id) & t.organizationId.equals(orgId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) throw const AcademicValidationException(AcademicIssue.notFound);
    return row;
  }

  Future<void> _setYearStatus(AcademicYearRow row, AcademicYearStatus status) async {
    final ts = now();
    await (db.update(db.academicYears)..where((t) => t.id.equals(row.id))).write(AcademicYearsCompanion(
      status: Value(status.name),
      updatedAt: Value(ts),
      updatedBy: Value(session.userId),
      deviceId: Value(session.deviceId),
      rowVersion: Value(row.rowVersion + 1),
    ));
    await changes.record(
      table: 'academic_years',
      rowId: row.id,
      operation: 'update',
      before: {'status': row.status},
      after: {'status': status.name},
    );
  }

  Future<void> _writeProgram(
    ProgramRow row,
    ProgramsCompanion change,
    Map<String, Object?> before,
    Map<String, Object?> after, {
    String operation = 'update',
  }) async {
    final ts = now();
    await (db.update(db.programs)..where((t) => t.id.equals(row.id))).write(change.copyWith(
      updatedAt: Value(ts),
      updatedBy: Value(session.userId),
      deviceId: Value(session.deviceId),
      rowVersion: Value(row.rowVersion + 1),
    ));
    await changes.record(table: 'programs', rowId: row.id, operation: operation, before: before, after: after);
  }

  Future<void> _writeDivision(
    DivisionRow row,
    DivisionsCompanion change,
    Map<String, Object?> before,
    Map<String, Object?> after, {
    String operation = 'update',
  }) async {
    final ts = now();
    await (db.update(db.divisions)..where((t) => t.id.equals(row.id))).write(change.copyWith(
      updatedAt: Value(ts),
      updatedBy: Value(session.userId),
      deviceId: Value(session.deviceId),
      rowVersion: Value(row.rowVersion + 1),
    ));
    await changes.record(table: 'divisions', rowId: row.id, operation: operation, before: before, after: after);
  }

  static DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static String _iso(DateTime d) => _dateOnly(d).toIso8601String().substring(0, 10);

  static AcademicYear _year(AcademicYearRow r) => AcademicYear(
        id: r.id,
        label: r.label,
        startDate: r.startDate,
        endDate: r.endDate,
        status: AcademicYearStatus.values.firstWhere((s) => s.name == r.status, orElse: () => AcademicYearStatus.inactive),
      );

  static Program _program(ProgramRow r) => Program(
        id: r.id,
        name: r.name,
        stream: r.stream,
        levelOrder: r.levelOrder,
        nextProgramId: r.nextProgramId,
      );

  static Division _division(DivisionRow r) => Division(
        id: r.id,
        programId: r.programId,
        academicYearId: r.academicYearId,
        name: r.name,
        displayOrder: r.displayOrder,
        capacity: r.capacity,
      );
}
