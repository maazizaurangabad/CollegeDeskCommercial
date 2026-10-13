import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/data/data_providers.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_models.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(sessionProvider),
    ref.watch(appSettingsRepositoryProvider),
  ),
);

/// Bumped after attendance or its settings change, so screens reload.
final attendanceRevisionProvider = StateProvider<int>((ref) => 0);

final attendanceCodesProvider = FutureProvider<List<AttendanceCode>>((ref) {
  ref.watch(attendanceRevisionProvider);
  return ref.watch(attendanceRepositoryProvider).codes();
});

/// Today's totals across all divisions, for the dashboard.
final todayAttendanceProvider = FutureProvider<({int marked, int present, int absent})>((ref) {
  ref.watch(attendanceRevisionProvider);
  return ref.watch(attendanceRepositoryProvider).dayTotals(DateTime.now());
});
