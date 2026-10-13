import 'package:flutter/foundation.dart';

/// How a mark counts towards the attendance percentage.
enum CountsAs { present, absent, half, excluded }

@immutable
class AttendanceCode {
  const AttendanceCode({
    required this.id,
    required this.code,
    required this.label,
    required this.colorValue,
    required this.countsAs,
    required this.displayOrder,
  });

  final String id;
  final String code;
  final String label;
  final int colorValue;
  final CountsAs countsAs;
  final int displayOrder;
}

/// A student who belongs on a division's sheet on a given date.
@immutable
class RosterEntry {
  const RosterEntry({
    required this.studentId,
    required this.enrollmentId,
    required this.fullName,
    required this.displayCode,
    this.rollNumber,
    this.photoFileName,
  });

  final String studentId;
  final String enrollmentId;
  final String fullName;
  final String displayCode;
  final int? rollNumber;
  final String? photoFileName;
}

enum DayKind { working, weeklyOff, holiday, exam }

@immutable
class DayInfo {
  const DayInfo({required this.date, required this.kind, required this.isFuture, required this.isLocked, this.note});

  final DateTime date;
  final DayKind kind;
  final bool isFuture;

  /// Older than the edit window: can be viewed, not changed.
  final bool isLocked;
  final String? note;

  /// Attendance is normally marked on working days and exam days.
  bool get isMarkable => !isFuture && (kind == DayKind.working || kind == DayKind.exam);
}

/// Everything the marking screen shows for one division and date.
@immutable
class AttendanceSheet {
  const AttendanceSheet({
    required this.day,
    required this.roster,
    required this.marks,
    this.sessionId,
    this.savedAt,
    this.savedBy,
  });

  final DayInfo day;
  final List<RosterEntry> roster;

  /// studentId -> code. Empty when not marked yet.
  final Map<String, String> marks;
  final String? sessionId;
  final DateTime? savedAt;
  final String? savedBy;

  bool get isSaved => sessionId != null;
}

@immutable
class AttendanceSummary {
  const AttendanceSummary({required this.present, required this.absent, required this.excluded, required this.days});

  static const empty = AttendanceSummary(present: 0, absent: 0, excluded: 0, days: 0);

  /// Half days count as 0.5.
  final double present;
  final double absent;
  final int excluded;

  /// Days with any mark.
  final int days;

  double? get percent => (present + absent) == 0 ? null : present * 100 / (present + absent);
}

/// One month of a division, for the register view.
@immutable
class MonthGrid {
  const MonthGrid({
    required this.year,
    required this.month,
    required this.students,
    required this.marks,
    required this.totals,
    required this.dayKinds,
  });

  final int year;
  final int month;
  final List<RosterEntry> students;

  /// studentId -> day of month -> code
  final Map<String, Map<int, String>> marks;
  final Map<String, AttendanceSummary> totals;

  /// day of month -> kind (holidays and weekly offs shaded)
  final Map<int, DayKind> dayKinds;

  int get daysInMonth => DateTime(year, month + 1, 0).day;
}

enum AttendanceIssue { futureDate, notWorkingDay, locked, unknownCode, codeInUse, duplicateCode, emptyCode }

class AttendanceException implements Exception {
  const AttendanceException(this.issue, [this.detail]);

  final AttendanceIssue issue;
  final String? detail;

  @override
  String toString() => 'AttendanceException(${issue.name})';
}

@immutable
class CalendarEntry {
  const CalendarEntry({required this.id, required this.date, required this.kind, required this.note});

  final String id;
  final DateTime date;
  final DayKind kind;
  final String note;
}
