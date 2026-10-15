import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/l10n/gen/app_localizations_en.dart';
import 'package:shiksha_desk/modules/attendance/data/attendance_repository.dart';
import 'package:shiksha_desk/modules/reports/application/report_builders.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/modules/students/presentation/student_picker.dart';
import 'package:shiksha_desk/platform/academic/academic_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/reporting/pdf_report_renderer.dart';
import 'package:shiksha_desk/platform/reporting/report_dataset.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

void main() {
  final today = DateTime(2026, 10, 14, 11);
  final l10n = AppLocalizationsEn();
  late AppDatabase db;
  late AcademicSnapshot academic;
  late AttendanceRepository attendance;
  late StudentRepository students;
  late ReportBuilders reports;
  late List<String> ids;
  late String divA;

  setUp(() async {
    db = newMemoryDatabase();
    await InstitutionCreator(db, testSession).create(
      profile: DemoData.organization,
      yearLabel: '2026-27',
      yearStart: DateTime(2026, 6, 1),
      yearEnd: DateTime(2027, 4, 30),
      template: StructureTemplate.juniorCollege,
      registry: buildModuleRegistry(),
    );
    final academicRepo = AcademicRepository(db, testSession);
    academic = await academicRepo.loadSnapshot();
    divA = academic.divisions.first.id;
    students = StudentRepository(db, testSession, testCipher);
    ids = [
      for (final (i, name) in ['Ayaan', 'Riya', 'Zoya'].indexed)
        await students.create(StudentDraft(
          firstName: name,
          divisionId: divA,
          rollNumber: i + 1,
          admissionDate: DateTime(2026, 6, 15),
          identifiers: {IdentifierType.grNumber: 'G${i + 1}'},
          guardians: [GuardianDraft(name: 'Parent $name', mobile: '98765432${i}0', isPrimary: true)],
        )),
    ];
    attendance = AttendanceRepository(db, testSession, AppSettingsRepository(db, testSession), clock: () => today);
    await attendance.setEditDays(30);
    // Riya absent 3 of 5 days; Zoya absent 1 of 5.
    final days = [5, 6, 7, 8, 9];
    for (var i = 0; i < days.length; i++) {
      await attendance.save(divA, DateTime(2026, 10, days[i]), {
        ids[0]: 'P',
        ids[1]: i < 3 ? 'A' : 'P',
        ids[2]: i == 0 ? 'A' : 'P',
      });
    }
    reports = ReportBuilders(
      l10n: l10n,
      academic: academic,
      attendance: attendance,
      students: students,
      divisionLabels: await academicRepo.divisionLabels(),
    );
  });
  tearDown(() => db.close());

  test('the monthly register has a column per day, totals and %', () async {
    final r = await reports.monthlyRegister(divA, 2026, 10);
    expect(r.columns, hasLength(2 + 31 + 3));
    expect(r.rows.map((x) => x.cells[1]), ['Ayaan', 'Riya', 'Zoya']);
    final riya = r.rows[1];
    expect(riya.cells[2 + 4], 'A'); // 5 October
    expect(riya.cells.last, '40');
    expect(riya.highlight, isTrue);
    expect(r.rows[0].cells.last, '100');
    expect(r.shadedColumns, contains(11 + 1)); // Sunday 11 October
  });

  test('defaulters and absentees list the right students with mobiles', () async {
    final d = await reports.defaulters(from: DateTime(2026, 10, 1), to: today);
    final data = d.rows.where((r) => r.kind == ReportRowKind.data).toList();
    expect(data.map((r) => r.cells[2]), ['Riya']);
    expect(data.single.cells[7], '9876543210');

    final a = await reports.absentees(DateTime(2026, 10, 5));
    expect(a.rows.where((r) => r.kind == ReportRowKind.data).map((r) => r.cells[1]), ['Riya', 'Zoya']);
    expect(a.rows.first.kind, ReportRowKind.group);
  });

  test('class list follows roll order and chosen columns; summary averages the division', () async {
    final c = await reports.classList(divA, {ClassListColumn.gr, ClassListColumn.mobile});
    expect(c.columns.map((x) => x.label), [l10n.reportRoll, l10n.fieldName, l10n.idGr, l10n.fieldMobile]);
    expect(c.rows.map((r) => r.cells[2]), ['G1', 'G2', 'G3']);

    final s = await reports.attendanceSummary(from: DateTime(2026, 10, 1), to: today);
    final row = s.rows.firstWhere((r) => r.cells[2] == '5');
    expect(row.cells[3], '${((100 + 40 + 80) / 3).toStringAsFixed(1)}%');
    expect(row.cells[4], '1');
  });

  test('class and master lists: sort by G.R., name or age, either order; Boys / Girls with their own counts', () async {
    // Ayaan (G1, boy, 2010), Riya (G2, girl, 2009), Zoya (G3, girl, no birth date) + Kabir (G10, boy, 2011).
    final details = {
      ids[0]: ('Male', DateTime(2010, 5, 1)),
      ids[1]: ('Female', DateTime(2009, 3, 1)),
      ids[2]: ('Female', null),
    };
    for (final e in details.entries) {
      final d = (await students.load(e.key))!.draft
        ..gender = e.value.$1
        ..dateOfBirth = e.value.$2;
      await students.update(e.key, d);
    }
    await students.create(StudentDraft(
      firstName: 'Kabir',
      gender: 'Male',
      dateOfBirth: DateTime(2011, 1, 1),
      divisionId: divA,
      rollNumber: 4,
      admissionDate: DateTime(2026, 6, 15),
      identifiers: {IdentifierType.grNumber: 'G10'},
    ));
    const show = {ClassListColumn.gr, ClassListColumn.gender};
    List<String> names(ReportDataset d) =>
        d.rows.where((r) => r.kind == ReportRowKind.data).map((r) => r.cells[1]).toList();

    expect(names(await reports.classList(divA, show, sort: StudentSort.gr)), ['Ayaan', 'Riya', 'Zoya', 'Kabir']);
    expect(names(await reports.classList(divA, show, sort: StudentSort.gr, descending: true)), ['Kabir', 'Zoya', 'Riya', 'Ayaan']);
    expect(names(await reports.classList(divA, show, sort: StudentSort.name)), ['Ayaan', 'Kabir', 'Riya', 'Zoya']);
    // Youngest first; no birth date last, in both orders.
    expect(names(await reports.classList(divA, show, sort: StudentSort.age)), ['Kabir', 'Ayaan', 'Riya', 'Zoya']);
    expect(names(await reports.classList(divA, show, sort: StudentSort.age, descending: true)), ['Riya', 'Ayaan', 'Kabir', 'Zoya']);

    final girls = await reports.classList(divA, show, sort: StudentSort.name, gender: GenderFilter.girls);
    expect(names(girls), ['Riya', 'Zoya']);
    expect(girls.notes.join(' '), contains('${l10n.reportTotal} 2'));
    expect(girls.notes.join(' '), isNot(contains(l10n.reportBoys)));
    expect(girls.subtitle.join(' '), contains(l10n.reportGirls));

    final boys = await reports.studentMaster(show: show, gender: GenderFilter.boys, sort: StudentSort.name);
    expect(names(boys), ['Ayaan', 'Kabir']);
    expect(boys.rows.firstWhere((r) => r.kind == ReportRowKind.group).groupTitle, contains('${l10n.reportTotal} 2'));
  });

  test('students with an unrecorded gender stay only in All students', () {
    expect(matchesGender(null, GenderFilter.all), isTrue);
    expect(matchesGender('', GenderFilter.boys), isFalse);
    expect(matchesGender('Other', GenderFilter.girls), isFalse);
    expect(matchesGender('female', GenderFilter.girls), isTrue);
    expect(matchesGender('M', GenderFilter.boys), isTrue);
    expect(compareNatural('2', '10'), lessThan(0));
    expect(compareNatural('10', '100'), lessThan(0));
  });

  test('a long report becomes a multi-page PDF with the letterhead', () async {
    final fonts = ReportFonts(
      ByteData.sublistView(File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync()),
      ByteData.sublistView(File('assets/fonts/NotoSans-Bold.ttf').readAsBytesSync()),
    );
    final data = ReportDataset(
      title: 'Test list',
      fileName: 'test',
      columns: const [ReportColumn('No', width: 30), ReportColumn('Name', flex: 1)],
      rows: [for (var i = 1; i <= 150; i++) ReportRow(['$i', 'Student number $i'])],
      signatures: const ['Principal'],
    );
    final bytes = await PdfReportRenderer.render(
      data,
      const ReportLetterhead(name: 'Test College', lines: ['Address line', 'UDISE: 123']),
      fonts,
    );
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(bytes)).length;
    expect(pages, greaterThanOrEqualTo(3));
  });
}
