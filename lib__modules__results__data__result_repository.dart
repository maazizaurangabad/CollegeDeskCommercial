import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/org_scoped_repository.dart';
import '../../../core/ids/uuid7.dart';
import '../../../platform/data/app_settings_repository.dart';
import '../../students/data/student_repository.dart';
import '../../students/domain/student_models.dart';
import '../domain/result_models.dart';

/// One line of a student's results: one exam, or (exam null) the final result.
typedef StudentExamResult = ({Exam? exam, StudentResult result});

/// Results: subjects per class, exams, subject choices, marks, and the
/// worked-out result. Every rule lives here or in [ResultCalculator].
class ResultRepository extends OrgScopedRepository {
  ResultRepository(super.db, super.session, this.settings, this.students);

  final AppSettingsRepository settings;
  final StudentRepository students;

  static const defaultExams = ['1st Term Examination', '2nd Term Examination'];

  // ================================================================= rules

  static const _wholeKey = 'results.whole_percent';
  static const _atktKey = 'results.atkt_subjects';
  static const _distinctionKey = 'results.distinction';
  static const _firstKey = 'results.first_class';
  static const _secondKey = 'results.second_class';

  Future<ResultRules> rules() async {
    const d = ResultRules();
    double numOr(String? v, double fallback) => double.tryParse(v ?? '') ?? fallback;
    return ResultRules(
      wholePercent: (await settings.getValue(_wholeKey)) != 'false',
      atktSubjects: int.tryParse(await settings.getValue(_atktKey) ?? '') ?? d.atktSubjects,
      distinction: numOr(await settings.getValue(_distinctionKey), d.distinction),
      firstClass: numOr(await settings.getValue(_firstKey), d.firstClass),
      secondClass: numOr(await settings.getValue(_secondKey), d.secondClass),
    );
  }

  Future<void> saveRules(ResultRules r) async {
    await settings.setValue(_wholeKey, '${r.wholePercent}');
    await settings.setValue(_atktKey, '${r.atktSubjects < 0 ? 0 : r.atktSubjects}');
    await settings.setValue(_distinctionKey, '${r.distinction}');
    await settings.setValue(_firstKey, '${r.firstClass}');
    await settings.setValue(_secondKey, '${r.secondClass}');
  }

  // ============================================================== subjects

  Future<List<Subject>> subjects({String? programId}) async {
    final q = db.select(db.subjects)
      ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.displayOrder), (t) => OrderingTerm.asc(t.name)]);
    if (programId != null) q.where((t) => t.programId.equals(programId));
    return [for (final r in await q.get()) _subject(r)];
  }

  static Subject _subject(SubjectRow r) => Subject(
        id: r.id,
        programId: r.programId,
        name: r.name,
        columnName: r.columnName,
        displayOrder: r.displayOrder,
        isGrade: r.kind == 'grade',
        maxMarks: r.maxMarks,
        passMarks: r.passMarks,
      );

  /// Adds a subject. [columnName] empty means its own column.
  Future<String> addSubject({
    required String programId,
    required String name,
    String columnName = '',
    bool isGrade = false,
    int maxMarks = 100,
    int passMarks = 35,
  }) {
    return db.transaction(() async {
      final clean = name.trim();
      if (clean.isEmpty) throw const ResultException(ResultIssue.emptyName);
      final existing = await subjects(programId: programId);
      if (existing.any((s) => s.name.toLowerCase() == clean.toLowerCase())) {
        throw const ResultException(ResultIssue.duplicate);
      }
      _checkMarks(isGrade, maxMarks, passMarks);
      final ts = now();
      final id = Uuid7.generate(ts);
      final column = columnName.trim().isEmpty ? clean : columnName.trim();
      // Alternatives sit next to each other: reuse the column's place.
      final sameColumn = existing.where((s) => s.columnName == column).firstOrNull;
      final order = sameColumn?.displayOrder ?? (existing.isEmpty ? 10 : existing.map((s) => s.displayOrder).reduce((a, b) => a > b ? a : b) + 10);
      await db.into(db.subjects).insert(SubjectsCompanion.insert(
            id: id,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            programId: programId,
            name: clean,
            columnName: column,
            displayOrder: Value(order),
            kind: Value(isGrade ? 'grade' : 'marks'),
            maxMarks: Value(isGrade ? 0 : maxMarks),
            passMarks: Value(isGrade ? 0 : passMarks),
          ));
      await changes.record(table: 'subjects', rowId: id, operation: 'insert', after: {
        'program': programId,
        'name': clean,
        'column': column,
        'kind': isGrade ? 'grade' : 'marks',
        'max': maxMarks,
        'pass': passMarks,
      });
      return id;
    });
  }

  static void _checkMarks(bool isGrade, int max, int pass) {
    if (isGrade) return;
    if (max <= 0 || pass < 0 || pass > max) throw const ResultException(ResultIssue.overMax);
  }

  Future<void> updateSubject(
    String id, {
    required String name,
    required String columnName,
    required bool isGrade,
    required int maxMarks,
    required int passMarks,
  }) {
    return db.transaction(() async {
      final row = await _subjectRow(id);
      final clean = name.trim();
      if (clean.isEmpty) throw const ResultException(ResultIssue.emptyName);
      final others = (await subjects(programId: row.programId)).where((s) => s.id != id);
      if (others.any((s) => s.name.toLowerCase() == clean.toLowerCase())) throw const ResultException(ResultIssue.duplicate);
      _checkMarks(isGrade, maxMarks, passMarks);
      final column = columnName.trim().isEmpty ? clean : columnName.trim();
      final sameColumn = others.where((s) => s.columnName == column).firstOrNull;
      await (db.update(db.subjects)..where((t) => t.id.equals(id))).write(SubjectsCompanion(
        name: Value(clean),
        columnName: Value(column),
        displayOrder: Value(sameColumn?.displayOrder ?? row.displayOrder),
        kind: Value(isGrade ? 'grade' : 'marks'),
        maxMarks: Value(isGrade ? 0 : maxMarks),
        passMarks: Value(isGrade ? 0 : passMarks),
        updatedAt: Value(now()),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(row.rowVersion + 1),
      ));
      await changes.record(
        table: 'subjects',
        rowId: id,
        operation: 'update',
        before: {'name': row.name, 'column': row.columnName, 'max': row.maxMarks, 'pass': row.passMarks},
        after: {'name': clean, 'column': column, 'max': maxMarks, 'pass': passMarks},
      );
    });
  }

  /// Moves a whole column up (-1) or down (+1) among the class's columns.
  Future<void> moveColumn(String programId, String columnName, int direction) {
    return db.transaction(() async {
      final cols = SubjectColumn.of(await subjects(programId: programId)).map((c) => c.name).toList();
      final i = cols.indexOf(columnName);
      final j = i + direction;
      if (i < 0 || j < 0 || j >= cols.length) return;
      cols.insert(j, cols.removeAt(i));
      final all = await subjects(programId: programId);
      for (var k = 0; k < cols.length; k++) {
        for (final s in all.where((s) => s.columnName == cols[k])) {
          await (db.update(db.subjects)..where((t) => t.id.equals(s.id)))
              .write(SubjectsCompanion(displayOrder: Value((k + 1) * 10), updatedAt: Value(now())));
        }
      }
    });
  }

  /// Only a subject with no marks can be deleted.
  Future<void> deleteSubject(String id) {
    return db.transaction(() async {
      final row = await _subjectRow(id);
      final used = await (db.select(db.marks)
            ..where((t) => t.organizationId.equals(orgId) & t.subjectId.equals(id) & t.deletedAt.isNull())
            ..limit(1))
          .get();
      if (used.isNotEmpty) throw const ResultException(ResultIssue.inUse);
      await (db.update(db.subjects)..where((t) => t.id.equals(id)))
          .write(SubjectsCompanion(deletedAt: Value(now()), updatedAt: Value(now())));
      await changes.record(table: 'subjects', rowId: id, operation: 'delete', after: {'name': row.name});
    });
  }

  Future<SubjectRow> _subjectRow(String id) async {
    final row = await (db.select(db.subjects)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
        .getSingleOrNull();
    if (row == null) throw const ResultException(ResultIssue.notFound);
    return row;
  }

  /// The usual HSC Science subjects (Maharashtra); skips any already there.
  Future<int> addScienceTemplate(String programId) async {
    final have = (await subjects(programId: programId)).map((s) => s.name.toLowerCase()).toSet();
    var added = 0;
    for (final (name, column, grade) in const [
      ('English', '', false),
      ('Urdu', 'Urdu/Arabic/Hindi', false),
      ('Arabic', 'Urdu/Arabic/Hindi', false),
      ('Hindi', 'Urdu/Arabic/Hindi', false),
      ('Physics', '', false),
      ('Chemistry', '', false),
      ('Biology', '', false),
      ('Mathematics', 'Maths/Socio', false),
      ('Sociology', 'Maths/Socio', false),
      ('Env. Sci.', '', true),
      ('Phy. Edu.', '', true),
    ]) {
      if (have.contains(name.toLowerCase())) continue;
      await addSubject(programId: programId, name: name, columnName: column, isGrade: grade);
      added++;
    }
    return added;
  }

  /// Copies subjects from one class to another (skips names already there).
  Future<int> copySubjects({required String fromProgramId, required String toProgramId}) async {
    final have = (await subjects(programId: toProgramId)).map((s) => s.name.toLowerCase()).toSet();
    var added = 0;
    for (final s in await subjects(programId: fromProgramId)) {
      if (have.contains(s.name.toLowerCase())) continue;
      await addSubject(
        programId: toProgramId,
        name: s.name,
        columnName: s.columnName,
        isGrade: s.isGrade,
        maxMarks: s.isGrade ? 100 : s.maxMarks,
        passMarks: s.isGrade ? 35 : s.passMarks,
      );
      added++;
    }
    return added;
  }

  // ================================================================= exams

  /// Exams of the year in order. The first time, 1st Term and 2nd Term are
  /// added (the 2nd Term counts in the final result).
  Future<List<Exam>> exams(String academicYearId) async {
    var rows = await _examRows(academicYearId);
    if (rows.isEmpty) {
      await db.transaction(() async {
        for (var i = 0; i < defaultExams.length; i++) {
          await _insertExam(academicYearId, defaultExams[i], (i + 1) * 10, countsInFinal: i == defaultExams.length - 1);
        }
      });
      rows = await _examRows(academicYearId);
    }
    return [
      for (final r in rows)
        Exam(id: r.id, academicYearId: r.academicYearId, name: r.name, displayOrder: r.displayOrder, countsInFinal: r.countsInFinal),
    ];
  }

  Future<List<ExamRow>> _examRows(String yearId) => (db.select(db.exams)
        ..where((t) => t.organizationId.equals(orgId) & t.academicYearId.equals(yearId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.displayOrder)]))
      .get();

  Future<String> _insertExam(String yearId, String name, int order, {bool countsInFinal = false}) async {
    final ts = now();
    final id = Uuid7.generate(ts);
    await db.into(db.exams).insert(ExamsCompanion.insert(
          id: id,
          organizationId: orgId,
          createdAt: ts,
          updatedAt: ts,
          createdBy: Value(session.userId),
          updatedBy: Value(session.userId),
          deviceId: session.deviceId,
          academicYearId: yearId,
          name: name,
          displayOrder: Value(order),
          countsInFinal: Value(countsInFinal),
        ));
    await changes.record(table: 'exams', rowId: id, operation: 'insert', after: {'name': name, 'final': countsInFinal});
    return id;
  }

  Future<String> addExam(String academicYearId, String name) {
    return db.transaction(() async {
      final clean = name.trim();
      if (clean.isEmpty) throw const ResultException(ResultIssue.emptyName);
      final existing = await exams(academicYearId);
      if (existing.any((e) => e.name.toLowerCase() == clean.toLowerCase())) throw const ResultException(ResultIssue.duplicate);
      return _insertExam(academicYearId, clean, existing.isEmpty ? 10 : existing.last.displayOrder + 10);
    });
  }

  Future<void> updateExam(String id, {String? name, bool? countsInFinal}) {
    return db.transaction(() async {
      final row = await (db.select(db.exams)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId))).getSingleOrNull();
      if (row == null) throw const ResultException(ResultIssue.notFound);
      final clean = name?.trim() ?? row.name;
      if (clean.isEmpty) throw const ResultException(ResultIssue.emptyName);
      if (name != null &&
          (await _examRows(row.academicYearId)).any((e) => e.id != id && e.name.toLowerCase() == clean.toLowerCase())) {
        throw const ResultException(ResultIssue.duplicate);
      }
      await (db.update(db.exams)..where((t) => t.id.equals(id))).write(ExamsCompanion(
        name: Value(clean),
        countsInFinal: Value(countsInFinal ?? row.countsInFinal),
        updatedAt: Value(now()),
        updatedBy: Value(session.userId),
        rowVersion: Value(row.rowVersion + 1),
      ));
      await changes.record(
        table: 'exams',
        rowId: id,
        operation: 'update',
        before: {'name': row.name, 'final': row.countsInFinal},
        after: {'name': clean, 'final': countsInFinal ?? row.countsInFinal},
      );
    });
  }

  /// Only an exam with no marks can be deleted.
  Future<void> deleteExam(String id) {
    return db.transaction(() async {
      final used = await (db.select(db.marks)
            ..where((t) => t.organizationId.equals(orgId) & t.examId.equals(id) & t.deletedAt.isNull())
            ..limit(1))
          .get();
      if (used.isNotEmpty) throw const ResultException(ResultIssue.inUse);
      await (db.update(db.exams)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .write(ExamsCompanion(deletedAt: Value(now()), updatedAt: Value(now())));
      await changes.record(table: 'exams', rowId: id, operation: 'delete', after: {});
    });
  }

  // ================================================================ roster

  /// Current students of a class (division) in roll order, with GR numbers.
  Future<List<RosterStudent>> roster(String divisionId, String academicYearId) async {
    final rows = await (db.select(db.enrollments)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.divisionId.equals(divisionId) &
              t.academicYearId.equals(academicYearId) &
              t.deletedAt.isNull() &
              t.status.equals('active')))
        .get();
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r.studentId).toSet();
    final names = await students.namesFor(ids);
    final grs = {
      for (final i in await (db.select(db.studentIdentifiers)
            ..where((t) =>
                t.organizationId.equals(orgId) &
                t.deletedAt.isNull() &
                t.studentId.isIn(ids) &
                t.idType.equals(IdentifierType.grNumber.code)))
          .get())
        i.studentId: i.idValue,
    };
    final out = <RosterStudent>[
      for (final r in rows)
        if (names[r.studentId] != null)
          (id: r.studentId, name: names[r.studentId]!.fullName, roll: r.rollNumber, gr: grs[r.studentId]),
    ];
    out.sort((a, b) {
      final c = (a.roll ?? 9999).compareTo(b.roll ?? 9999);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return out;
  }

  // =============================================================== choices

  /// studentId -> column name -> subjectId, for the year.
  Future<Map<String, Map<String, String>>> choices(String academicYearId, Iterable<String> studentIds) async {
    final ids = studentIds.toSet();
    if (ids.isEmpty) return {};
    final rows = await (db.select(db.subjectChoices)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.academicYearId.equals(academicYearId) &
              t.deletedAt.isNull() &
              t.studentId.isIn(ids)))
        .get();
    final out = <String, Map<String, String>>{};
    for (final r in rows) {
      (out[r.studentId] ??= {})[r.columnName] = r.subjectId;
    }
    return out;
  }

  /// Sets which subject of [columnName] each of [studentIds] takes.
  Future<void> setChoice({
    required String academicYearId,
    required Iterable<String> studentIds,
    required String columnName,
    required String subjectId,
  }) {
    return db.transaction(() async {
      final ts = now();
      for (final studentId in studentIds) {
        final existing = await (db.select(db.subjectChoices)
              ..where((t) =>
                  t.organizationId.equals(orgId) &
                  t.academicYearId.equals(academicYearId) &
                  t.studentId.equals(studentId) &
                  t.columnName.equals(columnName) &
                  t.deletedAt.isNull()))
            .getSingleOrNull();
        if (existing != null) {
          if (existing.subjectId == subjectId) continue;
          await (db.update(db.subjectChoices)..where((t) => t.id.equals(existing.id))).write(SubjectChoicesCompanion(
            subjectId: Value(subjectId),
            updatedAt: Value(ts),
            updatedBy: Value(session.userId),
            rowVersion: Value(existing.rowVersion + 1),
          ));
        } else {
          await db.into(db.subjectChoices).insert(SubjectChoicesCompanion.insert(
                id: Uuid7.generate(ts),
                organizationId: orgId,
                createdAt: ts,
                updatedAt: ts,
                createdBy: Value(session.userId),
                updatedBy: Value(session.userId),
                deviceId: session.deviceId,
                studentId: studentId,
                academicYearId: academicYearId,
                columnName: columnName,
                subjectId: subjectId,
              ));
        }
        await changes.record(
          table: 'subject_choices',
          rowId: studentId,
          operation: 'set',
          before: existing == null ? null : {'subject': existing.subjectId},
          after: {'year': academicYearId, 'column': columnName, 'subject': subjectId},
        );
      }
    });
  }

  // ================================================================= marks

  /// examId -> studentId -> subjectId -> entry.
  Future<Map<String, Map<String, Map<String, MarkEntry>>>> marks(Iterable<String> examIds, Iterable<String> studentIds) async {
    final exams = examIds.toSet();
    final ids = studentIds.toSet();
    if (exams.isEmpty || ids.isEmpty) return {};
    final rows = await (db.select(db.marks)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.examId.isIn(exams) & t.studentId.isIn(ids)))
        .get();
    final out = <String, Map<String, Map<String, MarkEntry>>>{};
    for (final r in rows) {
      ((out[r.examId] ??= {})[r.studentId] ??= {})[r.subjectId] = MarkEntry(marks: r.marks, grade: r.grade, absent: r.absent);
    }
    return out;
  }

  /// Turns what was typed into an entry: "56", "AB" (absent), "A" (grade).
  /// Empty text means nothing entered. Throws for marks above the maximum.
  static MarkEntry? parse(String text, Subject subject) {
    final t = text.trim().toUpperCase();
    if (t.isEmpty) return null;
    if (t == 'AB' || t == 'ABS' || t == 'ABSENT') return const MarkEntry(absent: true);
    if (subject.isGrade) {
      if (!RegExp(r'^[A-Z][+\-]?$|^[A-Z][0-9]$').hasMatch(t)) throw ResultException(ResultIssue.badGrade, text);
      return MarkEntry(grade: t);
    }
    final n = int.tryParse(t);
    if (n == null || n < 0) throw ResultException(ResultIssue.badGrade, text);
    if (n > subject.maxMarks) throw ResultException(ResultIssue.overMax, text);
    return MarkEntry(marks: n);
  }

  /// Saves marks of one exam: studentId -> subjectId -> entry (null clears it).
  Future<int> saveMarks(String examId, Map<String, Map<String, MarkEntry?>> entries) {
    return db.transaction(() async {
      final ts = now();
      var changed = 0;
      final current = await marks([examId], entries.keys);
      for (final se in entries.entries) {
        for (final e in se.value.entries) {
          final old = current[examId]?[se.key]?[e.key];
          final value = e.value;
          if (old?.marks == value?.marks && old?.grade == value?.grade && (old?.absent ?? false) == (value?.absent ?? false)) {
            continue;
          }
          final row = await (db.select(db.marks)
                ..where((t) =>
                    t.organizationId.equals(orgId) &
                    t.examId.equals(examId) &
                    t.studentId.equals(se.key) &
                    t.subjectId.equals(e.key) &
                    t.deletedAt.isNull()))
              .getSingleOrNull();
          if (value == null) {
            if (row != null) {
              await (db.update(db.marks)..where((t) => t.id.equals(row.id)))
                  .write(MarksCompanion(deletedAt: Value(ts), updatedAt: Value(ts)));
            }
          } else if (row == null) {
            await db.into(db.marks).insert(MarksCompanion.insert(
                  id: Uuid7.generate(ts),
                  organizationId: orgId,
                  createdAt: ts,
                  updatedAt: ts,
                  createdBy: Value(session.userId),
                  updatedBy: Value(session.userId),
                  deviceId: session.deviceId,
                  examId: examId,
                  studentId: se.key,
                  subjectId: e.key,
                  marks: Value(value.marks),
                  grade: Value(value.grade),
                  absent: Value(value.absent),
                ));
          } else {
            await (db.update(db.marks)..where((t) => t.id.equals(row.id))).write(MarksCompanion(
              marks: Value(value.marks),
              grade: Value(value.grade),
              absent: Value(value.absent),
              updatedAt: Value(ts),
              updatedBy: Value(session.userId),
              deviceId: Value(session.deviceId),
              rowVersion: Value(row.rowVersion + 1),
            ));
          }
          await changes.record(
            table: 'marks',
            rowId: '$examId/${se.key}/${e.key}',
            operation: value == null ? 'delete' : 'set',
            before: old == null ? null : {'value': old.text},
            after: {'value': value?.text ?? ''},
          );
          changed++;
        }
      }
      return changed;
    });
  }

  // ================================================================ result

  /// The result of a class for one exam, or (no [examId]) the final result
  /// from the exams counted in it.
  Future<({List<SubjectColumn> columns, List<StudentResult> results, List<Exam> exams})> classResult({
    required String divisionId,
    required String programId,
    required String academicYearId,
    String? examId,
  }) async {
    final allExams = await exams(academicYearId);
    final used = examId != null
        ? allExams.where((e) => e.id == examId).toList()
        : allExams.where((e) => e.countsInFinal).toList();
    final columns = SubjectColumn.of(await subjects(programId: programId));
    final list = await roster(divisionId, academicYearId);
    final ids = list.map((s) => s.id);
    final results = ResultCalculator.compute(
      roster: list,
      columns: columns,
      examIds: used.map((e) => e.id).toList(),
      marks: await marks(used.map((e) => e.id), ids),
      choices: await choices(academicYearId, ids),
      rules: await rules(),
    );
    return (columns: columns, results: results, exams: used);
  }

  /// One student's final result from their latest class (also after they
  /// have left). Null when there are no counted exams or no subjects.
  Future<({StudentResult result, String yearLabel, String classLabel, List<Exam> exams, ResultRules rules})?> finalResultOf(
      String studentId) async {
    final enrollment = await (db.select(db.enrollments)
          ..where((t) => t.organizationId.equals(orgId) & t.studentId.equals(studentId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (enrollment == null) return null;
    final division = await (db.select(db.divisions)..where((t) => t.id.equals(enrollment.divisionId))).getSingleOrNull();
    if (division == null) return null;
    final program = await (db.select(db.programs)..where((t) => t.id.equals(division.programId))).getSingleOrNull();
    final year = await (db.select(db.academicYears)..where((t) => t.id.equals(enrollment.academicYearId))).getSingleOrNull();
    final used = (await exams(enrollment.academicYearId)).where((e) => e.countsInFinal).toList();
    final columns = SubjectColumn.of(await subjects(programId: division.programId));
    if (used.isEmpty || columns.isEmpty) return null;
    final name = (await students.namesFor([studentId]))[studentId]?.fullName ?? '';
    final rules = await this.rules();
    final results = ResultCalculator.compute(
      roster: [(id: studentId, name: name, roll: enrollment.rollNumber, gr: null)],
      columns: columns,
      examIds: used.map((e) => e.id).toList(),
      marks: await marks(used.map((e) => e.id), [studentId]),
      choices: await choices(enrollment.academicYearId, [studentId]),
      rules: rules,
    );
    return (
      result: results.single,
      yearLabel: year?.label ?? '',
      classLabel: '${program?.name ?? ''} ${division.name}'.trim(),
      exams: used,
      rules: rules,
    );
  }

  // =========================================================== one student

  /// One student's results for a year, for the profile: each exam with any
  /// marks for them, then the final result. Worked out exactly as the class
  /// result sheet (same rules; rank among the class). Only reads: no exams
  /// are created here. Null when the student had no class that year, or the
  /// class has no subjects or exams.
  Future<({List<StudentExamResult> lines, ResultRules rules})?> studentResults(
    String studentId,
    String academicYearId,
  ) async {
    final enrollment = await (db.select(db.enrollments)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.studentId.equals(studentId) &
              t.academicYearId.equals(academicYearId) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (enrollment == null) return null;
    final division = await (db.select(db.divisions)..where((t) => t.id.equals(enrollment.divisionId))).getSingleOrNull();
    if (division == null) return null;
    final columns = SubjectColumn.of(await subjects(programId: division.programId));
    final examRows = await _examRows(academicYearId);
    if (columns.isEmpty || examRows.isEmpty) return null;
    final allExams = [
      for (final r in examRows)
        Exam(id: r.id, academicYearId: r.academicYearId, name: r.name, displayOrder: r.displayOrder, countsInFinal: r.countsInFinal),
    ];

    // The whole class, so the rank is the same as on the result sheet.
    // A student who has left is worked out alone (no rank).
    var list = await roster(division.id, academicYearId);
    final inClass = list.any((r) => r.id == studentId);
    if (!inClass) {
      final name = (await students.namesFor([studentId]))[studentId]?.fullName ?? '';
      list = [(id: studentId, name: name, roll: enrollment.rollNumber, gr: null)];
    }
    final ids = list.map((r) => r.id).toList();
    final rules = await this.rules();
    final allMarks = await marks(allExams.map((e) => e.id), ids);
    final allChoices = await choices(academicYearId, ids);

    StudentResult? resultFor(List<String> examIds) {
      final computed = ResultCalculator.compute(
        roster: list,
        columns: columns,
        examIds: examIds,
        marks: {for (final id in examIds) if (allMarks[id] != null) id: allMarks[id]!},
        choices: allChoices,
        rules: rules,
      );
      final mine = computed.where((r) => r.studentId == studentId).firstOrNull;
      if (mine == null) return null;
      final anyEntered = mine.columns.values.any((c) => c.obtained != null || c.grade != null);
      if (!anyEntered) return null;
      return inClass ? mine : mine.withRank(null);
    }

    final lines = <StudentExamResult>[];
    for (final e in allExams) {
      final r = resultFor([e.id]);
      if (r != null) lines.add((exam: e, result: r));
    }
    final counted = allExams.where((e) => e.countsInFinal).map((e) => e.id).toList();
    if (counted.isNotEmpty) {
      final r = resultFor(counted);
      if (r != null) lines.add((exam: null, result: r));
    }
    return (lines: lines, rules: rules);
  }
}
