import 'package:intl/intl.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_models.dart';
import '../../../platform/reporting/report_dataset.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_models.dart';
import '../../attendance/presentation/attendance_labels.dart';
import '../../certificates/data/certificate_repository.dart';
import '../../certificates/domain/certificate_models.dart';
import '../../students/data/student_repository.dart';
import '../../students/domain/student_models.dart';
import '../../students/presentation/student_labels.dart';
import '../../students/presentation/student_picker.dart';

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
    this.certificates,
    this.certificateTitle,
  });

  final CertificateRepository? certificates;

  /// Display name of each certificate type.
  final String Function(CertificateKind kind)? certificateTitle;

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
        ReportColumn(l10n.reportRoll, width: 22, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.fieldName, flex: 1),
        for (var d = 1; d <= days; d++) ReportColumn('$d', width: 14.5, align: ReportAlign.center),
        ReportColumn(l10n.reportPresentShort, width: 24, align: ReportAlign.center),
        ReportColumn(l10n.reportDaysShort, width: 24, align: ReportAlign.center),
        ReportColumn('%', width: 26, align: ReportAlign.center, type: ReportColumnType.number),
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
        ReportColumn(l10n.reportSr, width: 24, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.reportRoll, width: 30, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.fieldName, flex: 3),
        ReportColumn(l10n.studentCode, width: 62),
        ReportColumn(l10n.reportPresentShort, width: 40, align: ReportAlign.center),
        ReportColumn(l10n.reportDaysShort, width: 40, align: ReportAlign.center),
        ReportColumn('%', width: 44, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.fieldMobile, width: 74),
      ],
      rows: rows,
      groupLabel: l10n.fieldClass,
      countLabels: ReportCountLabels(total: l10n.reportTotal, byValue: const {}),
      signatures: [l10n.reportClassTeacher, l10n.reportPrincipal],
    ).withCounts();
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
        ReportColumn(l10n.reportRoll, width: 34, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.fieldName, flex: 3),
        ReportColumn(l10n.studentCode, width: 66),
        ReportColumn(l10n.reportMark, width: 80),
        ReportColumn(l10n.fieldMobile, width: 80),
      ],
      rows: rows,
      groupLabel: l10n.fieldClass,
      countLabels: ReportCountLabels(total: l10n.reportTotal, byValue: const {}),
    ).withCounts();
  }

  // ------------------------------------------------------------ name lists

  ReportCountLabels get _genderCounts => ReportCountLabels(
        total: l10n.reportTotal,
        byValue: {'Male': l10n.reportBoys, 'Female': l10n.reportGirls},
      );

  /// Optional columns: label, index in exportRows, width, Excel type.
  Map<ClassListColumn, (String, int, double, ReportColumnType)> get _optional => {
        ClassListColumn.gender: (l10n.fieldGender, 6, 46, ReportColumnType.text),
        ClassListColumn.dateOfBirth: (l10n.fieldDateOfBirth, 7, 64, ReportColumnType.date),
        ClassListColumn.gr: (l10n.idGr, 8, 52, ReportColumnType.text),
        ClassListColumn.pen: (l10n.idPen, 9, 76, ReportColumnType.text),
        ClassListColumn.apaar: (l10n.idApaar, 10, 76, ReportColumnType.text),
        ClassListColumn.mobile: (l10n.fieldMobile, 12, 72, ReportColumnType.text),
        ClassListColumn.category: (l10n.fieldCategory, 13, 54, ReportColumnType.text),
        ClassListColumn.bloodGroup: (l10n.fieldBloodGroup, 14, 40, ReportColumnType.text),
      };

  /// "Girls · Sorted by Name (A–Z) · Age as on 15/10/2026" for the subtitle.
  String listOptionsLine({required StudentSort sort, required bool descending, required GenderFilter gender}) => [
        genderFilterLabel(l10n, gender),
        l10n.reportSortedBy(studentSortLabel(l10n, sort), descending ? l10n.orderDescending : l10n.orderAscending),
        if (sort == StudentSort.age) l10n.reportAgeAsOn(DateFormat('dd/MM/yyyy').format(DateTime.now())),
      ].join(' · ');

  /// Gender is always kept (it is needed for the Boys / Girls counts);
  /// it is just not shown as a column unless chosen.
  Future<ReportDataset> classList(
    String divisionId,
    Set<ClassListColumn> show, {
    StudentSort sort = StudentSort.roll,
    bool descending = false,
    GenderFilter gender = GenderFilter.all,
  }) async {
    final items = sortStudents(
      (await students.list(academicYearId: academic.activeYear?.id, status: StudentStatus.active))
          .where((s) => s.divisionId == divisionId && matchesGender(s.gender, gender))
          .toList(),
      sort,
      descending: descending,
    );
    final export = await students.exportRows(items, divisionLabels);
    final chosen = [
      for (final c in ClassListColumn.values)
        if (show.contains(c)) (c, _optional[c]!),
    ];
    final genderAt = chosen.indexWhere((c) => c.$1 == ClassListColumn.gender);
    return ReportDataset(
      title: l10n.reportClassListTitle,
      subtitle: [
        '${_label(divisionId)} · ${academic.activeYear?.label ?? ''}',
        listOptionsLine(sort: sort, descending: descending, gender: gender),
      ],
      fileName: 'class-list-${_slug(_label(divisionId))}${gender == GenderFilter.all ? '' : '-${gender.name}'}',
      landscape: chosen.length > 5,
      fontSize: 10,
      zebra: true,
      columns: [
        ReportColumn(l10n.reportRoll, width: 34, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.fieldName, flex: 3),
        for (final c in chosen) ReportColumn(c.$2.$1, width: c.$2.$3, type: c.$2.$4),
      ],
      rows: [
        for (var i = 0; i < items.length; i++)
          ReportRow([
            items[i].rollNumber?.toString() ?? '',
            items[i].fullName,
            for (final c in chosen) export[i][c.$2.$2],
          ]),
      ],
      filterColumns: {
        for (var i = 0; i < chosen.length; i++)
          if (const {ClassListColumn.gender, ClassListColumn.category, ClassListColumn.bloodGroup}.contains(chosen[i].$1)) i + 2,
      },
      countColumn: genderAt < 0 ? null : genderAt + 2,
      countLabels: _genderCounts,
      signatures: [l10n.reportClassTeacher],
    ).withCounts();
  }

  /// All students (or one class / status), grouped by class in roll order.
  Future<ReportDataset> studentMaster({
    String? programId,
    StudentStatus? status,
    Set<ClassListColumn>? show,
    StudentSort sort = StudentSort.roll,
    bool descending = false,
    GenderFilter gender = GenderFilter.all,
  }) async {
    var items = (await students.list(academicYearId: academic.activeYear?.id, status: status))
        .where((s) => matchesGender(s.gender, gender))
        .toList();
    if (programId != null) {
      final allowed = academic.divisionsOf(programId).map((d) => d.id).toSet();
      items = items.where((s) => allowed.contains(s.divisionId)).toList();
    }
    final order = {
      for (final (i, p) in academic.programs.indexed)
        for (final (j, d) in academic.divisionsOf(p.id).indexed) d.id: i * 100 + j,
    };
    // Grouped by class; inside each class in the chosen order.
    final position = {for (final (i, s) in sortStudents(items, sort, descending: descending).indexed) s.id: i};
    items.sort((a, b) {
      final byClass = (order[a.divisionId] ?? 99999).compareTo(order[b.divisionId] ?? 99999);
      return byClass != 0 ? byClass : position[a.id]!.compareTo(position[b.id]!);
    });
    final export = await students.exportRows(items, divisionLabels);
    final columnsShown = show ?? {ClassListColumn.gender, ClassListColumn.dateOfBirth, ClassListColumn.gr, ClassListColumn.mobile};
    final chosen = [
      for (final c in ClassListColumn.values)
        if (columnsShown.contains(c)) (c, _optional[c]!),
    ];
    final genderAt = chosen.indexWhere((c) => c.$1 == ClassListColumn.gender);
    final statusAt = 3 + chosen.length;
    final rows = <ReportRow>[];
    String? group;
    for (var i = 0; i < items.length; i++) {
      final cls = _label(items[i].divisionId);
      final heading = cls.isEmpty ? l10n.studentsNotPlaced : cls;
      if (heading != group) {
        group = heading;
        rows.add(ReportRow.group(heading));
      }
      rows.add(ReportRow([
        items[i].rollNumber?.toString() ?? '',
        items[i].fullName,
        export[i][0],
        for (final c in chosen) export[i][c.$2.$2],
        studentStatusLabel(l10n, items[i].status),
      ]));
    }
    return ReportDataset(
      title: l10n.reportMasterTitle,
      subtitle: [
        [
          academic.activeYear?.label ?? '',
          if (programId != null) academic.programs.where((p) => p.id == programId).firstOrNull?.name ?? '',
          status == null ? l10n.studentsFilterAll : studentStatusLabel(l10n, status),
        ].where((s) => s.isNotEmpty).join(' · '),
        listOptionsLine(sort: sort, descending: descending, gender: gender),
      ],
      fileName: 'student-master-list${gender == GenderFilter.all ? '' : '-${gender.name}'}',
      landscape: chosen.length > 4,
      fontSize: 9.5,
      zebra: true,
      groupLabel: l10n.fieldClass,
      columns: [
        ReportColumn(l10n.reportRoll, width: 32, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.fieldName, flex: 3),
        ReportColumn(l10n.studentCode, width: 64),
        for (final c in chosen) ReportColumn(c.$2.$1, width: c.$2.$3, type: c.$2.$4),
        ReportColumn(l10n.studentsFilterStatus, width: 46),
      ],
      rows: rows,
      filterColumns: {
        for (var i = 0; i < chosen.length; i++)
          if (const {ClassListColumn.gender, ClassListColumn.category, ClassListColumn.bloodGroup}.contains(chosen[i].$1)) i + 3,
        statusAt,
      },
      countColumn: genderAt < 0 ? null : genderAt + 3,
      countLabels: _genderCounts,
    ).withCounts();
  }

  // ------------------------------------------------------------ certificates

  /// The outward register of certificates: number, date, type, student,
  /// class, GR, purpose or reason, prints and status.
  Future<ReportDataset> certificateRegister({DateTime? from, DateTime? to, CertificateKind? kind, String query = ''}) async {
    final all = await certificates!.list(kind: kind, limit: 100000);
    return certificateRegisterOf(all, from: from, to: to, query: query, kind: kind);
  }

  ReportDataset certificateRegisterOf(
    List<CertificateRecord> all, {
    DateTime? from,
    DateTime? to,
    CertificateKind? kind,
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    final items = all.where((c) {
      final d = DateTime(c.issuedOn.year, c.issuedOn.month, c.issuedOn.day);
      if (from != null && d.isBefore(DateTime(from.year, from.month, from.day))) return false;
      if (to != null && d.isAfter(DateTime(to.year, to.month, to.day))) return false;
      if (kind != null && c.kind != kind) return false;
      if (q.isNotEmpty && !'${c.studentName} ${c.serialLabel} ${c.fields[CertField.grNumber] ?? ''}'.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final byDate = a.issuedOn.compareTo(b.issuedOn);
        return byDate != 0 ? byDate : a.serialLabel.compareTo(b.serialLabel);
      });
    String title(CertificateKind k) => (certificateTitle?.call(k) ?? k.name).split(' (').first;
    String status(CertificateRecord c) => c.status == CertificateStatus.cancelled
        ? '${l10n.certCancelled}: ${c.cancelReason ?? ''}'
        : (c.isDuplicate ? l10n.certDuplicate : l10n.certIssuedStatus);
    final counts = <CertificateKind, int>{};
    for (final c in items.where((c) => c.status == CertificateStatus.issued)) {
      counts[c.kind] = (counts[c.kind] ?? 0) + 1;
    }
    return ReportDataset(
      title: l10n.certRegisterReport,
      subtitle: [
        [
          if (from != null || to != null) '${from == null ? '…' : _date(from)} – ${to == null ? '…' : _date(to)}',
          if (kind != null) title(kind),
        ].join(' · '),
      ],
      fileName: 'certificate-register',
      landscape: true,
      fontSize: 9,
      zebra: true,
      columns: [
        ReportColumn(l10n.reportSr, width: 26, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.certOutwardNo, width: 92),
        ReportColumn(l10n.certIssueDate, width: 60, type: ReportColumnType.date),
        ReportColumn(l10n.certChooseType, width: 92),
        ReportColumn(l10n.fieldName, flex: 3),
        ReportColumn(l10n.fieldClass, width: 82),
        ReportColumn(l10n.idGr, width: 46),
        ReportColumn(l10n.certPurposeReason, flex: 2),
        ReportColumn(l10n.certPrintedColumn, width: 38, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.studentsFilterStatus, width: 70),
      ],
      rows: [
        for (var i = 0; i < items.length; i++)
          ReportRow(
            [
              '${i + 1}',
              items[i].serialLabel,
              DateFormat('dd/MM/yyyy').format(items[i].issuedOn),
              title(items[i].kind),
              items[i].studentName,
              items[i].fields[CertField.className] ?? '',
              items[i].fields[CertField.grNumber] ?? '',
              [
                items[i].fields[CertField.purpose] ?? '',
                if (items[i].kind == CertificateKind.leaving || items[i].kind == CertificateKind.nirgam)
                  items[i].fields[CertField.leavingReason] ?? '',
              ].where((x) => x.trim().isNotEmpty).join(' · '),
              '${items[i].printCount}',
              status(items[i]),
            ],
            highlight: items[i].status == CertificateStatus.cancelled,
          ),
      ],
      filterColumns: const {3, 9},
      notes: [
        '${l10n.reportTotal} ${items.where((c) => c.status == CertificateStatus.issued).length}'
            '${counts.isEmpty ? '' : ' · ${counts.entries.map((e) => '${title(e.key)} ${e.value}').join(' · ')}'}',
      ],
      signatures: [l10n.reportPrincipal],
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
