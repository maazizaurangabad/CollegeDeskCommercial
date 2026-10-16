import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/academic/academic_controller.dart';
import '../../../platform/academic/academic_models.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../attendance/domain/attendance_models.dart';
import '../../certificates/application/certificates_providers.dart';
import '../../certificates/domain/certificate_models.dart';
import '../../fees/application/fees_providers.dart';
import '../../fees/domain/fee_models.dart';
import '../../messages/application/messages_providers.dart';
import '../../messages/domain/message_models.dart';
import '../../results/application/results_providers.dart';
import '../../results/data/result_repository.dart';
import '../../results/domain/result_models.dart';
import '../domain/student_models.dart';
import 'students_providers.dart';

// The Student 360° profile only reads: every number comes from the
// module's own repository, with the module's own rules.

/// A student and the academic year the profile shows.
typedef StudentYearKey = ({String studentId, String yearId});

final studentDetailProvider = FutureProvider.autoDispose.family<StudentDetail?, String>((ref, studentId) {
  ref.watch(studentsRevisionProvider);
  return ref.watch(studentRepositoryProvider).load(studentId);
});

/// "11th Science A" for every division of every year (for class history).
final allDivisionLabelsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) {
  ref.watch(studentsRevisionProvider);
  return ref.watch(academicRepositoryProvider).divisionLabels();
});

AcademicYear? _year(Ref ref, String yearId) =>
    ref.watch(academicControllerProvider).years.where((y) => y.id == yearId).firstOrNull;

/// Attendance from the start of the year to its end (or today).
final studentAttendanceYearProvider = FutureProvider.autoDispose
    .family<({AttendanceSummary summary, List<(DateTime, String)> recent})?, StudentYearKey>((ref, key) {
  ref.watch(attendanceRevisionProvider);
  final year = _year(ref, key.yearId);
  if (year == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final to = year.endDate.isBefore(today) ? year.endDate : today;
  return ref.watch(attendanceRepositoryProvider).studentPeriod(key.studentId, from: year.startDate, to: to);
});

final studentFeesYearProvider = FutureProvider.autoDispose.family<FeeAccount, StudentYearKey>((ref, key) {
  ref.watch(feesRevisionProvider);
  return ref.watch(feeRepositoryProvider).account(key.studentId, key.yearId);
});

final studentResultsYearProvider = FutureProvider.autoDispose
    .family<({List<StudentExamResult> lines, ResultRules rules})?, StudentYearKey>((ref, key) {
  ref.watch(resultsRevisionProvider);
  return ref.watch(resultRepositoryProvider).studentResults(key.studentId, key.yearId);
});

/// Messages about days in the year.
final studentMessagesYearProvider = FutureProvider.autoDispose.family<List<MessageRecord>, StudentYearKey>((ref, key) {
  ref.watch(messagesRevisionProvider);
  final year = _year(ref, key.yearId);
  return ref.watch(messageRepositoryProvider).historyOfStudent(
        key.studentId,
        from: year?.startDate,
        to: year?.endDate,
        limit: 50,
      );
});

/// Every certificate of the student (all years), newest first.
final studentCertificatesProvider = FutureProvider.autoDispose.family<List<CertificateRecord>, String>((ref, studentId) {
  ref.watch(certificatesRevisionProvider);
  return ref.watch(certificateRepositoryProvider).list(studentId: studentId);
});

/// The years the profile can show: years the student was enrolled in, and
/// the active year. Newest first.
List<AcademicYear> profileYears(AcademicSnapshot academic, StudentDetail detail) {
  final ids = {for (final e in detail.enrollments) e.academicYearId, if (academic.activeYear != null) academic.activeYear!.id};
  return academic.years.where((y) => ids.contains(y.id)).toList()..sort((a, b) => b.startDate.compareTo(a.startDate));
}

/// The year the profile opens on: the active year if the student is in it,
/// else the student's latest year.
String? defaultProfileYear(AcademicSnapshot academic, StudentDetail detail) {
  final active = academic.activeYear;
  if (active != null && detail.enrollments.any((e) => e.academicYearId == active.id)) return active.id;
  final years = profileYears(academic, detail);
  final enrolled = years.where((y) => detail.enrollments.any((e) => e.academicYearId == y.id));
  return enrolled.firstOrNull?.id ?? active?.id;
}

/// The student's enrollment in a year (the newest if there are several).
EnrollmentInfo? enrollmentIn(StudentDetail detail, String? yearId) =>
    yearId == null ? null : detail.enrollments.where((e) => e.academicYearId == yearId).firstOrNull;
