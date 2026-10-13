import 'package:intl/intl.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_models.dart';
import '../../../platform/reporting/report_dataset.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_models.dart';
import '../../attendance/presentation/attendance_labels.dart';
import '../../students/data/student_repository.dart';
import '../../students/domain/student_models.dart';
import '../../students/presentation/student_labels.dart';

/// Columns of the class list that can be switched on or off.
enum ClassListColumn { gender, dateOfBirth, gr, pen, apaar, mobile, category, bloodGroup }

/// Builds each report's dataset from the repositories. Knows nothing about
/// PDF or screens; the reporting engine draws whatever this returns.
class ReportBuilders {
  ReportBuilders({
    required this.l10n,
    required this.academic,
    required this.attendance,
    required this.students,
    required this.divisionLabels,
  });

  final AppLocalizations l10n;
  final AcademicSnapshot academic;
  final AttendanceRepository attendance;
  final StudentRepository students;

  /// divisionId -> "11th Science A" (every year).
  final Map<String, String> divisionLabels;

  static const _absentColor = 0xFFC62828;
  static const _okColor = 0xFF2E7D32;

  String _label(String? divisionId) => divisionLabels[divisionId] ?? '';
  String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  static String _date(DateTime d) => DateFormat('d MMM y').format(d);

  // ------------------------------------------------------------ register

  Future<ReportDataset> monthlyRegister(String divisionId, int year, int month) async {
    final grid = await attendance.monthGrid(divisionId, year, month);
    final codes = {for (final c in await attendance.codes()) c.code: c};
    final days = grid.daysInMonth;
    final monthName = DateFormat('MMMM y').format(DateTime(year, month));
    final rows = <ReportRow>[];
    for (final s in grid.students) {
      final marks = grid.marks[s.studentId] ?? const {};
      final total = grid.totals[s.studentId] ?? AttendanceSummary.empty;
      final p = total.percent;
      rows.add(ReportRow(
        [
          s.rollNumber?.toString() ?? '',
          s.fullName,
          for (var d = 1; d <= days; d++) marks[d] ?? '',
          formatPercent(total.present),
          formatPercent(total.present + total.absent),
          p == null ? '' : formatPercent(p),
        ],
        highlight: p != null && p < 75,
        textColors: {
          for (var d = 1; d <= days; d++)
            if (codes[marks[d]] != null) d + 1: codes[marks[d]]!.colorValue,
        },
      ));
    }
    return ReportDataset(
      title: l10n.reportRegisterTitle,
      subtitle: ['${_label(divisionId)} · $monthName'],
      fileName: 'register-${_slug(_label(divisionId))}-$year-${month.toString().padLeft(2, '0')}',
      landscape: true,
      fontSize: 7,
      columns: [
        ReportColumn(l10n.reportRoll, width: 22, align: ReportAlign.center),
        ReportColumn(l10n.fieldName, flex: 1),
        for (var d = 1; d <= days; d++) ReportColumn('$d', width: 14.5, align: ReportAlign.center),
        ReportColumn(l10n.reportPresentShort, width: 24, align: ReportAlign.center),
        ReportColumn(l10n.reportDaysShort, width: 24, align: ReportAlign.center),
        ReportColumn('%', width: 26, align: ReportAlign.center),
      ],
      shadedColumns: {for (final d in grid.dayKinds.keys) d + 1},
      rows: rows,
      notes: [
        codes.values.map((c) => '${c.code} = ${c.label}').join('    '),
        l10n.reportRegisterNote,
      ],
      signatures: [l10n.reportClassTeacher, l10n.reportPrincipal],
    );
  }

  // ------------------------------------------------------------ defaulters

  Future<ReportDataset> defaulters({
    required DateTime from,
    required DateTime to,
    double threshold = 75,
    String? programId,
  }) async {
    final low = await attendance.lowAttendance(from: from, to: to, threshold: threshold, minDays: 1);
    final placed = {for (final s in await students.list(academicYearId: academic.activeYear?.id)) s.id: s};
    final allowed = programId == null ? null : academic.divisionsOf(programId).map((d) => d.id).toSet();
    final items = [
      for (final l in low)
        if (placed[l.studentId] case final s?)
          if (allowed == null || allowed.contains(s.divisionId)) (s, l.summary),
    ]..sort((a, b) {
        final byClass = _label(a.$1.divisionId).compareTo(_label(b.$1.divisionId));
        if (byClass != 0) return byClass;
        return (a.$1.rollNumber ?? 9999).compareTo(b.$1.rollNumber ?? 9999);
      });
    final rows = <ReportRow>[];
    String? group;
    var n = 0;
    for (final (s, summary) in items) {
      final cls = _label(s.divisionId);
      if (cls != group) {
        group = cls;
        rows.add(ReportRow.group(cls.isEmpty ? l10n.studentsNotPlaced : cls));
      }
      n++;
      rows.add(ReportRow(
        [
          '$n',
          s.rollNumber?.toString() ?? '',
          s.fullName,
          s.displayCode,
          formatPercent(summary.present),
          formatPercent(summary.present + summary.absent),
          '${formatPercent(summary.percent)}%',
          s.primaryMobile ?? '',
        ],
        textColors: const {6: _absentColor},
      ));
    }
    return ReportDataset(
      title: l10n.reportDefaultersTitle(formatPercent(threshold)),
      subtitle: [
        '${_date(from)} – ${_date(to)}',
        if (programId != null) academic.programs.where((p) => p.id == programId).firstOrNull?.name ?? '',
      ],
      fileName: 'defaulters-${DateFormat('yyyy-MM-dd').format(to)}',
      columns: [
        ReportColumn(l10n.reportSr, width: 24, align: ReportAlign.center),
        ReportColumn(l10n.reportRoll, width: 30, align: ReportAlign.center),
        ReportColumn(l10n.fieldName, flex: 3),
        ReportColumn(l10n.studentCode, width: 62),
        ReportColumn(l10n.reportPresentShort, width: 40, align: ReportAlign.center),
        ReportColumn(l10n.reportDaysShort, width: 40, align: ReportAlign.center),
        ReportColumn('%', width: 44, align: ReportAlign.center),
        ReportColumn(l10n.fieldMobile, width: 74),
      ],
      rows: rows,
      notes: [l10n.reportCount(n)],
      signatures: [l10n.reportClassTeacher, l10n.reportPrincipal],
    );
  }

  // ------------------------------------------------------------ absentees

  Future<ReportDataset> absentees(DateTime date) async {
    final absent = await attendance.absentOn(date);
    final codes = {for (final c in await attendance.codes()) c.code: c};
    final placed = {for (final s in await students.list(academicYearId: academic.activeYear?.id)) s.id: s};
    final items = [
      for (final a in absent)
        if (placed[a.studentId] case final s?) (s, a.divisionId, a.code),
    ]..sort((a, b) {
        final byClass = _label(a.$2).compareTo(_label(b.$2));
        return byClass != 0 ? byClass : (a.$1.rollNumber ?? 9999).compareTo(b.$1.rollNumber ?? 9999);
      });
    final rows = <ReportRow>[];
    String? group;
    for (final (s, division, code) in items) {
      if (_label(division) != group) {
        group = _label(division);
        rows.add(ReportRow.group(group));
      }
      rows.add(ReportRow(
        [s.rollNumber?.toString() ?? '', s.fullName, s.displayCode, '$code · ${codes[code]?.label ?? ''}', s.primaryMobile ?? ''],
        textColors: {3: codes[code]?.colorValue ?? _absentColor},
      ));
    }
    return ReportDataset(
      title: l10n.reportAbsenteesTitle,
      subtitle: [DateFormat('EEEE, d MMMM y').format(date)],
      fileName: 'absentees-${DateFormat('yyyy-MM-dd').format(date)}',
      columns: [
        ReportColumn(l10n.reportRoll, width: 34, align: ReportAlign.center),
        ReportColumn(l10n.fieldName, flex: 3),
        ReportColumn(l10n.studentCode, width: 66),
        ReportColumn(l10n.reportMark, width: 80),
        ReportColumn(l10n.fieldMobile, width: 80),
      ],
      rows: rows,
      notes: [l10n.reportCount(items.length)],
    );
  }

  // ------------------------------------------------------------ class list

  Future<ReportDataset> classList(String divisionId, Set<ClassListColumn> show) async {
    final items = (await students.list(academicYearId: academic.activeYear?.id, status: StudentStatus.active))
        .where((s) => s.divisionId == divisionId)
        .toList()
      ..sort((a, b) => (a.rollNumber ?? 9999).compareTo(b.rollNumber ?? 9999));
    final export = await students.exportRows(items, divisionLabels);
    // exportRows columns: code, first, middle, last, class, roll, gender, dob, gr, pen, apaar, saral, mobile, category, blood, status
    final optional = <ClassListColumn, (String, int, double)>{
      ClassListColumn.gender: (l10n.fieldGender, 6, 44),
      ClassListColumn.dateOfBirth: (l10n.fieldDateOfBirth, 7, 60),
      ClassListColumn.gr: (l10n.idGr, 8, 50),
      ClassListColumn.pen: (l10n.idPen, 9, 70),
      ClassListColumn.apaar: (l10n.idApaar, 10, 70),
      ClassListColumn.mobile: (l10n.fieldMobile, 12, 70),
      ClassListColumn.category: (l10n.fieldCategory, 13, 50),
      ClassListColumn.bloodGroup: (l10n.fieldBloodGroup, 14, 36),
    };
    final chosen = [for (final c in ClassListColumn.values) if (show.contains(c)) optional[c]!];
    return ReportDataset(
      title: l10n.reportClassListTitle,
      subtitle: ['${_label(divisionId)} · ${academic.activeYear?.label ?? ''}'],
      fileName: 'class-list-${_slug(_label(divisionId))}',
      landscape: chosen.length > 5,
      columns: [
        ReportColumn(l10n.reportRoll, width: 30, align: ReportAlign.center),
        ReportColumn(l10n.fieldName, flex: 3),
        for (final c in chosen) ReportColumn(c.$1, width: c.$3),
      ],
      rows: [
        for (var i = 0; i < items.length; i++)
          ReportRow([
            items[i].rollNumber?.toString() ?? '',
            items[i].fullName,
            for (final c in chosen) export[i][c.$2],
          ]),
      ],
      notes: [l10n.reportCount(items.length)],
      signatures: [l10n.reportClassTeacher],
    );
  }

  // ------------------------------------------------------------ master list

  Future<ReportDataset> studentMaster({String? programId, StudentStatus? status}) async {
    var items = await students.list(academicYearId: academic.activeYear?.id, status: status);
    if (programId != null) {
      final allowed = academic.divisionsOf(programId).map((d) => d.id).toSet();
      items = items.where((s) => allowed.contains(s.divisionId)).toList();
    }
    items.sort((a, b) {
      final byClass = _label(a.divisionId).compareTo(_label(b.divisionId));
      return byClass != 0 ? byClass : (a.rollNumber ?? 9999).compareTo(b.rollNumber ?? 9999);
    });
    final export = await students.exportRows(items, divisionLabels);
    return ReportDataset(
      title: l10n.reportMasterTitle,
      subtitle: [
        [
          if (programId != null) academic.programs.where((p) => p.id == programId).firstOrNull?.name ?? '',
          status == null ? l10n.studentsFilterAll : studentStatusLabel(l10n, status),
        ].where((s) => s.isNotEmpty).join(' · '),
      ],
      fileName: 'student-list',
      landscape: true,
      columns: [
        ReportColumn(l10n.reportSr, width: 24, align: ReportAlign.center),
        ReportColumn(l10n.studentCode, width: 60),
        ReportColumn(l10n.fieldName, flex: 3),
        ReportColumn(l10n.fieldClass, width: 90),
        ReportColumn(l10n.reportRoll, width: 28, align: ReportAlign.center),
        ReportColumn(l10n.fieldGender, width: 42),
        ReportColumn(l10n.fieldDateOfBirth, width: 58),
        ReportColumn(l10n.idGr, width: 48),
        ReportColumn(l10n.idPen, width: 66),
        ReportColumn(l10n.fieldMobile, width: 66),
        ReportColumn(l10n.studentsFilterStatus, width: 44),
      ],
      rows: [
        for (var i = 0; i < items.length; i++)
          ReportRow([
            '${i + 1}',
            export[i][0],
            items[i].fullName,
            export[i][4],
            export[i][5],
            export[i][6],
            export[i][7],
            export[i][8],
            export[i][9],
            export[i][12],
            studentStatusLabel(l10n, items[i].status),
          ]),
      ],
      notes: [l10n.reportCount(items.length)],
    );
  }

  // ------------------------------------------------------------ summary

  Future<ReportDataset> attendanceSummary({required DateTime from, required DateTime to}) async {
    final summaries = await attendance.divisionSummaries(from: from, to: to);
    final ordered = [
      for (final p in academic.programs)
        for (final d in academic.divisionsOf(p.id)) d.id,
    ];
    final rows = <ReportRow>[];
    for (final id in ordered) {
      final s = summaries[id];
      final avg = s?.average;
      rows.add(ReportRow(
        [
          _label(id),
          '${s?.students ?? (await attendance.roster(id, to)).length}',
          '${s?.days ?? 0}',
          avg == null ? '—' : '${formatPercent(avg)}%',
          '${s?.below ?? 0}',
        ],
        highlight: avg != null && avg < 75,
        textColors: {
          if (avg != null) 3: avg < 75 ? _absentColor : _okColor,
          if ((s?.below ?? 0) > 0) 4: _absentColor,
        },
      ));
    }
    return ReportDataset(
      title: l10n.reportSummaryTitle,
      subtitle: ['${_date(from)} – ${_date(to)}'],
      fileName: 'attendance-summary-${DateFormat('yyyy-MM-dd').format(to)}',
      columns: [
        ReportColumn(l10n.fieldDivision, flex: 3),
        ReportColumn(l10n.reportStudents, width: 60, align: ReportAlign.center),
        ReportColumn(l10n.reportDaysMarked, width: 80, align: ReportAlign.center),
        ReportColumn(l10n.reportAverage, width: 80, align: ReportAlign.center),
        ReportColumn(l10n.reportBelow75, width: 80, align: ReportAlign.center),
      ],
      rows: rows,
      signatures: [l10n.reportPrincipal],
    );
  }
}
