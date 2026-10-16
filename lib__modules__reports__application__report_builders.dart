import 'dart:convert';
import 'dart:typed_data';

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

/// Columns a student list (class list, master list) can show. The order
/// here is only the order of the old fixed layout; users arrange their own.
enum ClassListColumn {
  gender,
  dateOfBirth,
  gr,
  pen,
  apaar,
  mobile,
  category,
  bloodGroup,
  motherName,
  fatherName,
  aadhaar,
  serial,
  roll,
  name,
  code,
  status,

  /// Only in the Student Register with Photograph.
  photo,
}

/// The order and choice of columns in a student list, as the user set it.
abstract final class StudentListLayout {
  static const classListDefault = [
    ClassListColumn.serial,
    ClassListColumn.roll,
    ClassListColumn.name,
    ClassListColumn.gender,
    ClassListColumn.dateOfBirth,
    ClassListColumn.gr,
    ClassListColumn.mobile,
  ];

  static const masterDefault = [
    ClassListColumn.serial,
    ClassListColumn.roll,
    ClassListColumn.name,
    ClassListColumn.code,
    ClassListColumn.gender,
    ClassListColumn.dateOfBirth,
    ClassListColumn.gr,
    ClassListColumn.mobile,
    ClassListColumn.status,
  ];

  static const photoRegisterDefault = [
    ClassListColumn.serial,
    ClassListColumn.name,
    ClassListColumn.motherName,
    ClassListColumn.dateOfBirth,
    ClassListColumn.photo,
  ];

  /// Always shown: Sr. No. (first) and Name.
  static const fixed = {ClassListColumn.serial, ClassListColumn.name};

  /// Columns offered for a report (Status only on the master list, Photo
  /// only on the photo register).
  static List<ClassListColumn> available({required bool master, bool photo = false}) => [
        for (final c in ClassListColumn.values)
          if (_allowed(c, master: master, photo: photo)) c,
      ];

  static bool _allowed(ClassListColumn c, {required bool master, required bool photo}) =>
      (master || c != ClassListColumn.status) && (photo || c != ClassListColumn.photo);

  static List<ClassListColumn> defaults({required bool master, bool photo = false}) =>
      photo ? photoRegisterDefault : (master ? masterDefault : classListDefault);

  /// A usable layout: no repeats, Sr. No. first, Name present, Status only
  /// on the master list, Aadhaar off unless chosen. Columns without Name
  /// are the old "extra columns" form: Roll, Name (and Code and Status on
  /// the master list) around the extras, in the old order.
  static List<ClassListColumn> normalise(Iterable<ClassListColumn> columns, {required bool master, bool photo = false}) {
    final chosen = <ClassListColumn>[];
    for (final c in columns) {
      if (!chosen.contains(c) && _allowed(c, master: master, photo: photo)) chosen.add(c);
    }
    if (!chosen.contains(ClassListColumn.name)) {
      const fixedOld = {
        ClassListColumn.serial,
        ClassListColumn.roll,
        ClassListColumn.name,
        ClassListColumn.code,
        ClassListColumn.status,
        ClassListColumn.photo,
      };
      return [
        ClassListColumn.roll,
        ClassListColumn.name,
        if (master) ClassListColumn.code,
        for (final c in ClassListColumn.values)
          if (chosen.contains(c) && !fixedOld.contains(c)) c,
        if (master) ClassListColumn.status,
      ];
    }
    chosen.remove(ClassListColumn.serial);
    return [ClassListColumn.serial, ...chosen];
  }

  /// Saved as a JSON list of names; anything unreadable gives the default.
  static List<ClassListColumn> decode(String? raw, {required bool master, bool photo = false}) {
    if (raw == null) return defaults(master: master, photo: photo);
    try {
      final names = (jsonDecode(raw) as List<dynamic>).map((e) => '$e');
      final columns = [
        for (final n in names)
          if (ClassListColumn.values.where((c) => c.name == n).firstOrNull case final c?) c,
      ];
      if (!columns.contains(ClassListColumn.name)) return defaults(master: master, photo: photo);
      return normalise(columns, master: master, photo: photo);
    } catch (_) {
      return defaults(master: master, photo: photo);
    }
  }

  static String encode(List<ClassListColumn> layout) => jsonEncode([for (final c in layout) c.name]);
}

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
    this.photoBytes,
  });

  /// Reads a student's photo file (for the photo register); null when absent.
  final Future<Uint8List?> Function(String fileName)? photoBytes;

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
        const ReportColumn('%', width: 26, align: ReportAlign.center, type: ReportColumnType.number),
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
        const ReportColumn('%', width: 44, align: ReportAlign.center, type: ReportColumnType.number),
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

  /// Label, fixed width or flex share, alignment and Excel type of a column.
  ({String label, double? width, double? flex, ReportAlign align, ReportColumnType type}) _spec(ClassListColumn c) =>
      switch (c) {
        ClassListColumn.serial =>
          (label: l10n.reportSr, width: 26, flex: null, align: ReportAlign.center, type: ReportColumnType.number),
        ClassListColumn.roll =>
          (label: l10n.reportRoll, width: 32, flex: null, align: ReportAlign.center, type: ReportColumnType.number),
        ClassListColumn.name =>
          (label: l10n.fieldName, width: null, flex: 3, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.code =>
          (label: l10n.studentCode, width: 64, flex: null, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.gender =>
          (label: l10n.fieldGender, width: 46, flex: null, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.dateOfBirth =>
          (label: l10n.fieldDateOfBirth, width: 64, flex: null, align: ReportAlign.left, type: ReportColumnType.date),
        ClassListColumn.gr => (label: l10n.idGr, width: 52, flex: null, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.pen => (label: l10n.idPen, width: 76, flex: null, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.apaar =>
          (label: l10n.idApaar, width: 76, flex: null, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.aadhaar =>
          (label: l10n.idAadhaar, width: 84, flex: null, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.motherName =>
          (label: l10n.reportMotherName, width: null, flex: 2, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.fatherName =>
          (label: l10n.fieldFatherName, width: null, flex: 2, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.mobile =>
          (label: l10n.fieldMobile, width: 72, flex: null, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.category =>
          (label: l10n.fieldCategory, width: 54, flex: null, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.bloodGroup =>
          (label: l10n.fieldBloodGroup, width: 40, flex: null, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.status =>
          (label: l10n.studentsFilterStatus, width: 46, flex: null, align: ReportAlign.left, type: ReportColumnType.text),
        ClassListColumn.photo =>
          (label: l10n.reportPhoto, width: 66, flex: null, align: ReportAlign.center, type: ReportColumnType.text),
      };

  /// Column name shown in the column chooser.
  String columnLabel(ClassListColumn c) => _spec(c).label;

  /// "Girls · Sorted by Name (A–Z) · Age as on 15/10/2026" for the subtitle.
  String listOptionsLine({required StudentSort sort, required bool descending, required GenderFilter gender}) => [
        genderFilterLabel(l10n, gender),
        l10n.reportSortedBy(studentSortLabel(l10n, sort), descending ? l10n.orderDescending : l10n.orderAscending),
        if (sort == StudentSort.age) l10n.reportAgeAsOn(DateFormat('dd/MM/yyyy').format(DateTime.now())),
      ].join(' · ');

  /// The columns, rows and summary of a student list in [layout] order.
  /// [groupBy] gives each student's group heading (the master list groups
  /// by class); Sr. No. runs on across groups. With [fullAadhaar] the
  /// Aadhaar column holds full numbers (each reveal is logged); otherwise
  /// only the masked form XXXX XXXX 1234.
  Future<({List<ReportColumn> columns, List<ReportRow> rows, Set<int> filters, int? countAt})> _nameList(
    List<StudentListItem> items,
    List<ClassListColumn> layout, {
    String Function(StudentListItem s)? groupBy,
    bool fullAadhaar = false,
    Map<ClassListColumn, String> labels = const {},
  }) async {
    final export = await students.exportRows(items, divisionLabels);
    final needsFacts = layout.any((c) => const {
          ClassListColumn.motherName,
          ClassListColumn.fatherName,
          ClassListColumn.aadhaar,
          ClassListColumn.photo,
        }.contains(c));
    final ids = items.map((s) => s.id);
    final facts = needsFacts ? await students.reportFacts(ids) : const <String, StudentReportFacts>{};
    final full = fullAadhaar && layout.contains(ClassListColumn.aadhaar)
        ? await students.revealAadhaarFor(ids)
        : const <String, String>{};
    // Photos, read once; only JPEG/PNG the PDF can draw.
    final photoAt = layout.indexOf(ClassListColumn.photo);
    final photos = <String, Uint8List>{};
    final loader = photoBytes;
    if (photoAt >= 0 && loader != null) {
      for (final s in items) {
        final file = facts[s.id]?.photoFileName;
        if (file == null) continue;
        final raw = await loader(file);
        if (raw != null && isJpegOrPng(raw)) photos[s.id] = raw;
      }
    }

    String value(ClassListColumn c, int i, int serial) {
      final s = items[i];
      final e = export[i];
      final f = facts[s.id];
      return switch (c) {
        ClassListColumn.serial => '$serial',
        ClassListColumn.roll => s.rollNumber?.toString() ?? '',
        ClassListColumn.name => s.fullName,
        ClassListColumn.code => e[0],
        ClassListColumn.gender => e[6],
        ClassListColumn.dateOfBirth => e[7],
        ClassListColumn.gr => e[8],
        ClassListColumn.pen => e[9],
        ClassListColumn.apaar => e[10],
        ClassListColumn.mobile => e[12],
        ClassListColumn.category => e[13],
        ClassListColumn.bloodGroup => e[14],
        ClassListColumn.motherName => f?.motherName ?? '',
        ClassListColumn.fatherName => f?.fatherName ?? '',
        ClassListColumn.aadhaar => full[s.id] ?? f?.aadhaarMasked ?? '',
        ClassListColumn.status => studentStatusLabel(l10n, s.status),
        ClassListColumn.photo => photos.containsKey(s.id) ? l10n.reportPhotoOnFile : l10n.reportNoPhoto,
      };
    }

    final rows = <ReportRow>[];
    String? group;
    for (var i = 0; i < items.length; i++) {
      if (groupBy != null) {
        final heading = groupBy(items[i]);
        if (heading != group) {
          group = heading;
          rows.add(ReportRow.group(heading));
        }
      }
      final photo = photos[items[i].id];
      rows.add(ReportRow(
        [for (final c in layout) value(c, i, i + 1)],
        images: {if (photoAt >= 0 && photo != null) photoAt: photo},
      ));
    }
    final columns = [
      for (final c in layout)
        ReportColumn(labels[c] ?? _spec(c).label,
            width: _spec(c).width, flex: _spec(c).flex, align: _spec(c).align, type: _spec(c).type),
    ];
    return (
      columns: columns,
      rows: rows,
      filters: {
        for (var i = 0; i < layout.length; i++)
          if (const {
            ClassListColumn.gender,
            ClassListColumn.category,
            ClassListColumn.bloodGroup,
            ClassListColumn.status,
          }.contains(layout[i]))
            i,
      },
      countAt: layout.contains(ClassListColumn.gender) ? layout.indexOf(ClassListColumn.gender) : null,
    );
  }

  /// Landscape when the columns would not fit across A4 portrait.
  bool _wide(List<ReportColumn> columns) {
    final fixed = columns.fold<double>(0, (sum, c) => sum + (c.width ?? 0));
    final flex = columns.fold<double>(0, (sum, c) => sum + (c.flex ?? 0));
    return fixed + flex * 45 > 539;
  }

  List<String> _aadhaarNotes(bool fullAadhaar, List<ClassListColumn> layout) => [
        if (layout.contains(ClassListColumn.aadhaar))
          fullAadhaar ? l10n.reportAadhaarFullNote : l10n.reportAadhaarMaskedNote,
      ];

  /// Gender is always kept (it is needed for the Boys / Girls counts);
  /// it is just not shown as a column unless chosen. [columns] is the
  /// layout in order (see [StudentListLayout]); a set of extra columns
  /// without Name keeps the old fixed layout (Roll, Name, extras).
  Future<ReportDataset> classList(
    String divisionId,
    Iterable<ClassListColumn> columns, {
    StudentSort sort = StudentSort.roll,
    bool descending = false,
    GenderFilter gender = GenderFilter.all,
    bool fullAadhaar = false,
  }) async {
    final layout = StudentListLayout.normalise(columns, master: false);
    final items = sortStudents(
      (await students.list(academicYearId: academic.activeYear?.id, status: StudentStatus.active))
          .where((s) => s.divisionId == divisionId && matchesGender(s.gender, gender))
          .toList(),
      sort,
      descending: descending,
    );
    final list = await _nameList(items, layout, fullAadhaar: fullAadhaar);
    return ReportDataset(
      title: l10n.reportClassListTitle,
      subtitle: [
        '${_label(divisionId)} · ${academic.activeYear?.label ?? ''}',
        listOptionsLine(sort: sort, descending: descending, gender: gender),
      ],
      fileName: 'class-list-${_slug(_label(divisionId))}${gender == GenderFilter.all ? '' : '-${gender.name}'}'
          '${fullAadhaar && layout.contains(ClassListColumn.aadhaar) ? '-confidential' : ''}',
      landscape: _wide(list.columns),
      fontSize: 10,
      zebra: true,
      columns: list.columns,
      rows: list.rows,
      filterColumns: list.filters,
      countColumn: list.countAt,
      countLabels: _genderCounts,
      notes: _aadhaarNotes(fullAadhaar, layout),
      signatures: [l10n.reportClassTeacher],
    ).withCounts();
  }

  /// All students (or one class / status), grouped by class; inside each
  /// class in the chosen order.
  Future<ReportDataset> studentMaster({
    String? programId,
    StudentStatus? status = StudentStatus.active,
    Iterable<ClassListColumn>? show,
    StudentSort sort = StudentSort.roll,
    bool descending = false,
    GenderFilter gender = GenderFilter.all,
    bool fullAadhaar = false,
  }) async {
    final layout = StudentListLayout.normalise(show ?? StudentListLayout.masterDefault, master: true);
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
    final position = {for (final (i, s) in sortStudents(items, sort, descending: descending).indexed) s.id: i};
    items.sort((a, b) {
      final byClass = (order[a.divisionId] ?? 99999).compareTo(order[b.divisionId] ?? 99999);
      return byClass != 0 ? byClass : position[a.id]!.compareTo(position[b.id]!);
    });
    final list = await _nameList(
      items,
      layout,
      fullAadhaar: fullAadhaar,
      groupBy: (s) {
        final cls = _label(s.divisionId);
        return cls.isEmpty ? l10n.studentsNotPlaced : cls;
      },
    );
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
      fileName: 'student-master-list${gender == GenderFilter.all ? '' : '-${gender.name}'}'
          '${fullAadhaar && layout.contains(ClassListColumn.aadhaar) ? '-confidential' : ''}',
      landscape: _wide(list.columns),
      fontSize: 9.5,
      zebra: true,
      groupLabel: l10n.fieldClass,
      columns: list.columns,
      rows: list.rows,
      filterColumns: list.filters,
      countColumn: list.countAt,
      countLabels: _genderCounts,
      notes: _aadhaarNotes(fullAadhaar, layout),
    ).withCounts();
  }

  // ------------------------------------------------------- photo register

  /// Student Register with Photograph for one class. The standard columns
  /// are Sr. No., Student Name, Mother's Name, Date of Birth, Photograph;
  /// [layout] can add, remove and reorder them like a class list. A4
  /// landscape; PDF, Word and Excel keep the photos.
  Future<ReportDataset> photoRegister(
    String divisionId, {
    Iterable<ClassListColumn>? layout,
    StudentSort sort = StudentSort.roll,
    bool descending = false,
    GenderFilter gender = GenderFilter.all,
    bool fullAadhaar = false,
  }) async {
    final columns = StudentListLayout.normalise(
      layout ?? StudentListLayout.photoRegisterDefault,
      master: false,
      photo: true,
    );
    final items = sortStudents(
      (await students.list(academicYearId: academic.activeYear?.id, status: StudentStatus.active))
          .where((s) => s.divisionId == divisionId && matchesGender(s.gender, gender))
          .toList(),
      sort,
      descending: descending,
    );
    final list = await _nameList(
      items,
      columns,
      fullAadhaar: fullAadhaar,
      labels: {
        ClassListColumn.serial: l10n.reportSrNo,
        ClassListColumn.name: l10n.reportStudentName,
        ClassListColumn.photo: l10n.reportPhoto,
      },
    );
    final photoAt = columns.indexOf(ClassListColumn.photo);
    return ReportDataset(
      title: l10n.reportPhotoRegisterTitle,
      subtitle: [
        '${_label(divisionId)} · ${academic.activeYear?.label ?? ''}',
        listOptionsLine(sort: sort, descending: descending, gender: gender),
      ],
      fileName: 'photo-register-${_slug(_label(divisionId))}${gender == GenderFilter.all ? '' : '-${gender.name}'}'
          '${fullAadhaar && columns.contains(ClassListColumn.aadhaar) ? '-confidential' : ''}',
      landscape: true,
      fontSize: 10.5,
      columns: [
        for (final (i, c) in list.columns.indexed)
          // Sr. No. a little wider here.
          i == 0 ? ReportColumn(c.label, width: 40, align: c.align, type: c.type) : c,
      ],
      rows: list.rows,
      imageColumns: {if (photoAt >= 0) photoAt},
      imageHeight: 60,
      filterColumns: list.filters,
      countLabels: ReportCountLabels(total: l10n.reportTotal, byValue: const {}),
      notes: _aadhaarNotes(fullAadhaar, columns),
      signatures: [l10n.reportClassTeacher, l10n.reportPrincipal],
    ).withCounts();
  }

  /// A photo the PDF can draw: JPEG or PNG (checked by its first bytes).
  static bool isJpegOrPng(Uint8List b) =>
      (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) ||
      (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47);

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
