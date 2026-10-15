import 'package:flutter/foundation.dart';

@immutable
class Subject {
  const Subject({
    required this.id,
    required this.programId,
    required this.name,
    required this.columnName,
    required this.displayOrder,
    required this.isGrade,
    required this.maxMarks,
    required this.passMarks,
  });

  final String id;
  final String programId;
  final String name;

  /// Subjects sharing a column are alternatives (each student takes one).
  final String columnName;
  final int displayOrder;

  /// Grade-only (A, B...), not added to the total.
  final bool isGrade;
  final int maxMarks;
  final int passMarks;
}

/// One column of the result sheet: one subject, or a choice of subjects.
@immutable
class SubjectColumn {
  const SubjectColumn({required this.name, required this.subjects});

  final String name;
  final List<Subject> subjects;

  bool get isGrade => subjects.first.isGrade;
  bool get isChoice => subjects.length > 1;

  /// Columns of a class in order; marks columns first, grade columns after.
  static List<SubjectColumn> of(List<Subject> subjects) {
    final sorted = [...subjects]..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final order = <String>[];
    final byName = <String, List<Subject>>{};
    for (final s in sorted) {
      final key = s.columnName.trim().isEmpty ? s.name : s.columnName.trim();
      if (!byName.containsKey(key)) order.add(key);
      (byName[key] ??= []).add(s);
    }
    final cols = [for (final k in order) SubjectColumn(name: k, subjects: byName[k]!)];
    return [...cols.where((c) => !c.isGrade), ...cols.where((c) => c.isGrade)];
  }
}

@immutable
class Exam {
  const Exam({
    required this.id,
    required this.academicYearId,
    required this.name,
    required this.displayOrder,
    required this.countsInFinal,
  });

  final String id;
  final String academicYearId;
  final String name;
  final int displayOrder;
  final bool countsInFinal;
}

/// What was entered for one student in one subject of one exam.
@immutable
class MarkEntry {
  const MarkEntry({this.marks, this.grade, this.absent = false});

  final int? marks;
  final String? grade;
  final bool absent;

  /// What is shown in the entry box: 56, AB, or A.
  String get text => absent ? 'AB' : (grade ?? marks?.toString() ?? '');
}

/// How results are worked out. Kept in settings so every institution can
/// use its own rules.
@immutable
class ResultRules {
  const ResultRules({
    this.wholePercent = true,
    this.atktSubjects = 0,
    this.distinction = 75,
    this.firstClass = 60,
    this.secondClass = 45,
  });

  /// Percentage shown as a whole number (52) instead of 52.00.
  final bool wholePercent;

  /// Failed in up to this many subjects: ATKT (allowed to keep terms). 0 = off.
  final int atktSubjects;
  final double distinction;
  final double firstClass;
  final double secondClass;

  String percentText(double p) => wholePercent ? '${p.round()}' : p.toStringAsFixed(2);
}

enum ResultStatus { passed, failed, atkt, incomplete }

enum ResultClass { distinction, first, second, pass }

/// A student's mark in one column of the sheet.
@immutable
class ColumnResult {
  const ColumnResult({
    required this.subject,
    this.obtained,
    this.max = 0,
    this.absent = false,
    this.passed = true,
    this.grade,
    this.missing = false,
  });

  /// The subject the student takes in this column (null: not chosen).
  final Subject? subject;
  final int? obtained;
  final int max;
  final bool absent;
  final bool passed;
  final String? grade;

  /// Marks not entered yet.
  final bool missing;

  String get text {
    if (grade != null) return grade!;
    if (missing) return '-';
    if (absent && (obtained ?? 0) == 0) return 'AB';
    return obtained?.toString() ?? '-';
  }
}

@immutable
class StudentResult {
  const StudentResult({
    required this.studentId,
    required this.name,
    required this.columns,
    required this.total,
    required this.maxTotal,
    required this.status,
    required this.failedSubjects,
    this.rollNumber,
    this.grNumber,
    this.resultClass,
    this.rank,
  });

  final String studentId;
  final String name;
  final int? rollNumber;
  final String? grNumber;

  /// Column name -> result.
  final Map<String, ColumnResult> columns;
  final int total;
  final int maxTotal;
  final ResultStatus status;
  final int failedSubjects;
  final ResultClass? resultClass;
  final int? rank;

  double get percent => maxTotal == 0 ? 0 : total * 100 / maxTotal;

  StudentResult withRank(int? r) => StudentResult(
        studentId: studentId,
        name: name,
        columns: columns,
        total: total,
        maxTotal: maxTotal,
        status: status,
        failedSubjects: failedSubjects,
        rollNumber: rollNumber,
        grNumber: grNumber,
        resultClass: resultClass,
        rank: r,
      );
}

/// A student on the class list: (id, name, roll, GR).
typedef RosterStudent = ({String id, String name, int? roll, String? gr});

/// Works out results. Pure: the same inputs always give the same result.
abstract final class ResultCalculator {
  /// [examIds]: the exams added together (one exam, or the exams counted in
  /// the final result). [marks]: examId -> studentId -> subjectId -> entry.
  /// [choices]: studentId -> column name -> subjectId.
  static List<StudentResult> compute({
    required List<RosterStudent> roster,
    required List<SubjectColumn> columns,
    required List<String> examIds,
    required Map<String, Map<String, Map<String, MarkEntry>>> marks,
    required Map<String, Map<String, String>> choices,
    required ResultRules rules,
  }) {
    final n = examIds.length;
    final out = <StudentResult>[];
    for (final st in roster) {
      final cols = <String, ColumnResult>{};
      var total = 0, maxTotal = 0, failed = 0;
      var incomplete = n == 0;
      for (final c in columns) {
        final subject = _subjectFor(st.id, c, examIds, marks, choices);
        if (subject == null) {
          cols[c.name] = ColumnResult(subject: null, missing: !c.isGrade);
          if (!c.isGrade) incomplete = true;
          continue;
        }
        if (c.isGrade) {
          String? grade;
          for (final e in examIds) {
            final g = marks[e]?[st.id]?[subject.id];
            if (g == null) continue;
            final value = g.grade ?? '';
            if (value.isNotEmpty) grade = value;
            if (g.absent) grade ??= 'AB';
          }
          cols[c.name] = ColumnResult(subject: subject, grade: grade, missing: grade == null);
          continue;
        }
        var obtained = 0, absentAll = true, missing = false;
        for (final e in examIds) {
          final m = marks[e]?[st.id]?[subject.id];
          if (m == null || (!m.absent && m.marks == null)) {
            missing = true;
            continue;
          }
          if (!m.absent) absentAll = false;
          obtained += m.absent ? 0 : (m.marks ?? 0);
        }
        final max = subject.maxMarks * n;
        if (missing) {
          incomplete = true;
          cols[c.name] = ColumnResult(subject: subject, missing: true, max: max);
          continue;
        }
        final passed = obtained >= subject.passMarks * n;
        if (!passed) failed++;
        total += obtained;
        maxTotal += max;
        cols[c.name] = ColumnResult(subject: subject, obtained: obtained, max: max, absent: absentAll, passed: passed);
      }
      final status = incomplete
          ? ResultStatus.incomplete
          : failed == 0
              ? ResultStatus.passed
              : (failed <= rules.atktSubjects ? ResultStatus.atkt : ResultStatus.failed);
      final percent = maxTotal == 0 ? 0.0 : total * 100 / maxTotal;
      out.add(StudentResult(
        studentId: st.id,
        name: st.name,
        rollNumber: st.roll,
        grNumber: st.gr,
        columns: cols,
        total: total,
        maxTotal: maxTotal,
        status: status,
        failedSubjects: failed,
        resultClass: status == ResultStatus.passed ? classFor(percent, rules) : null,
      ));
    }
    return rank(out);
  }

  static ResultClass classFor(double percent, ResultRules rules) {
    if (percent >= rules.distinction) return ResultClass.distinction;
    if (percent >= rules.firstClass) return ResultClass.first;
    if (percent >= rules.secondClass) return ResultClass.second;
    return ResultClass.pass;
  }

  /// Ranks passed students by total (equal totals share a rank: 1, 2, 2, 4).
  static List<StudentResult> rank(List<StudentResult> list) {
    final passed = list.where((r) => r.status == ResultStatus.passed).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final ranks = <String, int>{};
    for (var i = 0; i < passed.length; i++) {
      ranks[passed[i].studentId] =
          (i > 0 && passed[i].total == passed[i - 1].total) ? ranks[passed[i - 1].studentId]! : i + 1;
    }
    return [for (final r in list) r.withRank(ranks[r.studentId])];
  }

  static Subject? _subjectFor(
    String studentId,
    SubjectColumn c,
    List<String> examIds,
    Map<String, Map<String, Map<String, MarkEntry>>> marks,
    Map<String, Map<String, String>> choices,
  ) {
    if (!c.isChoice) return c.subjects.first;
    final chosen = choices[studentId]?[c.name];
    if (chosen != null) {
      final s = c.subjects.where((s) => s.id == chosen).firstOrNull;
      if (s != null) return s;
    }
    // No choice saved: the subject the student has marks in.
    for (final s in c.subjects) {
      for (final e in examIds) {
        if (marks[e]?[studentId]?[s.id] != null) return s;
      }
    }
    return null;
  }
}

enum ResultIssue { emptyName, duplicate, inUse, overMax, badGrade, notFound }

class ResultException implements Exception {
  const ResultException(this.issue, [this.detail]);

  final ResultIssue issue;
  final String? detail;

  @override
  String toString() => 'ResultException(${issue.name}${detail == null ? '' : ': $detail'})';
}
