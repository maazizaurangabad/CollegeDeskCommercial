import '../../../l10n/gen/app_localizations.dart';
import '../domain/attendance_models.dart';

String attendanceErrorMessage(AppLocalizations l10n, Object error) {
  if (error is! AttendanceException) return l10n.saveFailed;
  return switch (error.issue) {
    AttendanceIssue.futureDate => l10n.attendanceErrFuture,
    AttendanceIssue.notWorkingDay => l10n.attendanceErrNotWorking,
    AttendanceIssue.locked => l10n.attendanceErrLocked,
    AttendanceIssue.unknownCode => l10n.attendanceErrUnknown,
    AttendanceIssue.codeInUse => l10n.attendanceErrInUse,
    AttendanceIssue.duplicateCode => l10n.attendanceErrDuplicate,
    AttendanceIssue.emptyCode => l10n.attendanceErrEmpty,
  };
}

String countsAsLabel(AppLocalizations l10n, CountsAs c) => switch (c) {
      CountsAs.present => l10n.countsPresent,
      CountsAs.absent => l10n.countsAbsent,
      CountsAs.half => l10n.countsHalf,
      CountsAs.excluded => l10n.countsExcluded,
    };

List<String> weekdayShort(AppLocalizations l10n) =>
    [l10n.weekMon, l10n.weekTue, l10n.weekWed, l10n.weekThu, l10n.weekFri, l10n.weekSat, l10n.weekSun];

String formatPercent(double? p) => p == null ? '—' : p.toStringAsFixed(p >= 99.95 || p == p.roundToDouble() ? 0 : 1);
