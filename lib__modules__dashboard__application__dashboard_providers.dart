import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/activity_repository.dart';
import '../../../platform/data/data_providers.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../attendance/domain/attendance_models.dart';
import '../../certificates/application/certificates_providers.dart';
import '../../certificates/domain/certificate_models.dart';
import '../../students/application/students_providers.dart';
import '../../students/domain/student_models.dart';

/// Divisions of the active year not yet marked today (empty on holidays).
final unmarkedTodayProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(attendanceRevisionProvider);
  ref.watch(studentsRevisionProvider);
  final repo = ref.watch(attendanceRepositoryProvider);
  final academic = ref.watch(academicControllerProvider);
  final day = await repo.dayInfo(DateTime.now());
  if (!day.isMarkable) return const [];
  return repo.unmarkedDivisions(DateTime.now(), academic.divisions.map((d) => d.id));
});

class AbsentToday {
  const AbsentToday(this.student, this.divisionId, this.code);

  final StudentListItem student;
  final String divisionId;
  final String code;
}

final absentTodayProvider = FutureProvider<List<AbsentToday>>((ref) async {
  ref.watch(attendanceRevisionProvider);
  final rows = await ref.watch(attendanceRepositoryProvider).absentOn(DateTime.now());
  final names = await ref.watch(studentRepositoryProvider).namesFor(rows.map((r) => r.studentId));
  return [
    for (final r in rows)
      if (names[r.studentId] case final s?) AbsentToday(s, r.divisionId, r.code),
  ]..sort((a, b) => a.student.fullName.compareTo(b.student.fullName));
});

class LowAttendance {
  const LowAttendance(this.student, this.summary);

  final StudentListItem student;
  final AttendanceSummary summary;
}

/// This month so far, below 75% with at least 5 counted days.
final lowAttendanceProvider = FutureProvider<List<LowAttendance>>((ref) async {
  ref.watch(attendanceRevisionProvider);
  final now = DateTime.now();
  final rows = await ref.watch(attendanceRepositoryProvider).lowAttendance(from: DateTime(now.year, now.month), to: now);
  final names = await ref.watch(studentRepositoryProvider).namesFor(rows.map((r) => r.studentId));
  return [
    for (final r in rows)
      if (names[r.studentId] case final s? when s.status == StudentStatus.active) LowAttendance(s, r.summary),
  ];
});

final birthdaysTodayProvider = FutureProvider<List<StudentListItem>>((ref) {
  ref.watch(studentsRevisionProvider);
  return ref.watch(studentRepositoryProvider).birthdaysOn(DateTime.now());
});

final recentActivityProvider = FutureProvider<List<ActivityItem>>((ref) {
  ref.watch(studentsRevisionProvider);
  ref.watch(attendanceRevisionProvider);
  return ActivityRepository(ref.watch(appDatabaseProvider), ref.watch(sessionProvider)).recent();
});

/// Certificates issued this month, per type (cancelled ones not counted).
final certificatesThisMonthProvider = FutureProvider<Map<CertificateKind, int>>((ref) async {
  ref.watch(certificatesRevisionProvider);
  final now = DateTime.now();
  final all = await ref.watch(certificateRepositoryProvider).list(limit: 100000);
  final counts = <CertificateKind, int>{};
  for (final c in all) {
    if (c.status != CertificateStatus.issued) continue;
    if (c.issuedOn.year != now.year || c.issuedOn.month != now.month) continue;
    counts[c.kind] = (counts[c.kind] ?? 0) + 1;
  }
  return counts;
});
