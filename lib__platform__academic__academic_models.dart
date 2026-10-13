import 'package:flutter/foundation.dart';

enum AcademicYearStatus { active, inactive, closed }

@immutable
class AcademicYear {
  const AcademicYear({
    required this.id,
    required this.label,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  final String id;
  final String label;
  final DateTime startDate;
  final DateTime endDate;
  final AcademicYearStatus status;

  bool get isActive => status == AcademicYearStatus.active;
  bool get isClosed => status == AcademicYearStatus.closed;
}

@immutable
class Program {
  const Program({
    required this.id,
    required this.name,
    required this.levelOrder,
    this.stream,
    this.nextProgramId,
  });

  final String id;
  final String name;
  final String? stream;
  final int levelOrder;
  final String? nextProgramId;
}

@immutable
class Division {
  const Division({
    required this.id,
    required this.programId,
    required this.academicYearId,
    required this.name,
    required this.displayOrder,
    this.capacity,
  });

  final String id;
  final String programId;
  final String academicYearId;
  final String name;
  final int displayOrder;
  final int? capacity;
}

/// Why an academic change was refused. Screens turn these into messages.
enum AcademicIssue {
  emptyName,
  duplicateYear,
  duplicateProgram,
  duplicateDivision,
  endBeforeStart,
  programHasDivisions,
  divisionHasStudents,
  cannotCloseActiveYear,
  yearIsClosed,
  notFound,
}

class AcademicValidationException implements Exception {
  const AcademicValidationException(this.issue);

  final AcademicIssue issue;

  @override
  String toString() => 'AcademicValidationException(${issue.name})';
}

/// Everything the academic screens show, for the open institution.
@immutable
class AcademicSnapshot {
  const AcademicSnapshot({required this.years, required this.programs, required this.divisions});

  static const empty = AcademicSnapshot(years: [], programs: [], divisions: []);

  final List<AcademicYear> years;
  final List<Program> programs;

  /// Divisions of the active year only.
  final List<Division> divisions;

  AcademicYear? get activeYear {
    for (final y in years) {
      if (y.isActive) return y;
    }
    return null;
  }

  List<Division> divisionsOf(String programId) =>
      divisions.where((d) => d.programId == programId).toList()..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
}
