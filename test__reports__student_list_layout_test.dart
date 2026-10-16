import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/core/validation/aadhaar.dart';
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

const _c = ClassListColumn.values;

void main() {
  final l10n = AppLocalizationsEn();

  group('column layout', () {
    test('Sr. No. always first, no repeats, Status only on the master list', () {
      final layout = StudentListLayout.normalise(
        [ClassListColumn.gr, ClassListColumn.name, ClassListColumn.serial, ClassListColumn.gr, ClassListColumn.status],
        master: false,
      );
      expect(layout, [ClassListColumn.serial, ClassListColumn.gr, ClassListColumn.name]);
      expect(
        StudentListLayout.normalise([ClassListColumn.name, ClassListColumn.status], master: true),
        [ClassListColumn.serial, ClassListColumn.name, ClassListColumn.status],
      );
    });

    test('the old "extra columns" form keeps the old fixed layout', () {
      expect(
        StudentListLayout.normalise({ClassListColumn.mobile, ClassListColumn.gr}, master: false),
        [ClassListColumn.roll, ClassListColumn.name, ClassListColumn.gr, ClassListColumn.mobile],
      );
    });

    test('saved layouts are read back; unreadable ones give the standard layout', () {
      final mine = [
        ClassListColumn.serial,
        ClassListColumn.gr,
        ClassListColumn.name,
        ClassListColumn.motherName,
        ClassListColumn.dateOfBirth,
        ClassListColumn.aadhaar,
      ];
      expect(StudentListLayout.decode(StudentListLayout.encode(mine), master: false), mine);
      expect(StudentListLayout.decode(null, master: false), StudentListLayout.classListDefault);
      expect(StudentListLayout.decode('oops', master: true), StudentListLayout.masterDefault);
      expect(StudentListLayout.decode('["gr"]', master: false), StudentListLayout.classListDefault);
      expect(StudentListLayout.decode('["name","no_such_column"]', master: false), [ClassListColumn.serial, ClassListColumn.name]);
    });

    test('Aadhaar is not in the standard layouts', () {
      expect(StudentListLayout.classListDefault, isNot(contains(ClassListColumn.aadhaar)));
      expect(StudentListLayout.masterDefault, isNot(contains(ClassListColumn.aadhaar)));
      expect(_c, contains(ClassListColumn.aadhaar));
    });
  });

  test('sort by gender: boys, girls, others, then blank; same gender by name', () {
    StudentListItem item(String name, String? gender) => StudentListItem(
          id: name,
          displayCode: name,
          fullName: name,
          status: StudentStatus.active,
          gender: gender,
        );
    final items = [
      item('Zoya', 'Female'),
      item('Kabir', 'Male'),
      item('Noor', null),
      item('Ayaan', 'Male'),
      item('Alex', 'Other'),
      item('Riya', 'Female'),
    ];
    expect(sortStudents(items, StudentSort.gender).map((s) => s.fullName), ['Ayaan', 'Kabir', 'Riya', 'Zoya', 'Alex', 'Noor']);
    expect(
      sortStudents(items, StudentSort.gender, descending: true).map((s) => s.fullName),
      ['Alex', 'Riya', 'Zoya', 'Ayaan', 'Kabir', 'Noor'],
    );
  });

  group('with a database', () {
    late AppDatabase db;
    late StudentRepository students;
    late ReportBuilders reports;
    late String divA;
    late List<String> ids;
    final aadhaar = '23456789012${Aadhaar.checkDigit('23456789012')}';
    final photos = <String, Uint8List>{};

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
      final academic = await AcademicRepository(db, testSession).loadSnapshot();
      divA = academic.divisions.first.id;
      students = StudentRepository(db, testSession, testCipher);
      ids = [
        for (final (i, (name, gender)) in [('Ayaan', 'Male'), ('Riya', 'Female'), ('Zoya', 'Female')].indexed)
          await students.create(StudentDraft(
            firstName: name,
            gender: gender,
            divisionId: divA,
            rollNumber: i + 1,
            dateOfBirth: DateTime(2009, 3, 10 + i),
            admissionDate: DateTime(2026, 6, 15),
            identifiers: {
              IdentifierType.grNumber: 'G${i + 1}',
              if (i == 1) IdentifierType.aadhaar: aadhaar,
            },
            guardians: [
              GuardianDraft(name: 'Mother of $name', relation: 'Mother', mobile: '98765432${i}0', isPrimary: true),
              GuardianDraft(name: 'Father of $name', relation: 'Father'),
            ],
          )),
      ];
      final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 30, height: 40)));
      photos
        ..clear()
        ..['ayaan.jpg'] = jpeg
        ..['broken.jpg'] = Uint8List.fromList(utf8.encode('not a picture'));
      await students.setPhoto(ids[0], 'ayaan.jpg');
      await students.setPhoto(ids[2], 'broken.jpg');
      reports = ReportBuilders(
        l10n: l10n,
        academic: academic,
        attendance: AttendanceRepository(db, testSession, AppSettingsRepository(db, testSession)),
        students: students,
        divisionLabels: {divA: '11th Science A'},
        photoBytes: (name) async => photos[name],
      );
    });
    tearDown(() => db.close());

    List<ReportRow> data(ReportDataset d) => d.rows.where((r) => r.kind == ReportRowKind.data).toList();

    test('the PDF, Excel and CSV columns follow the chosen order exactly', () async {
      final d = await reports.classList(divA, const [
        ClassListColumn.serial,
        ClassListColumn.gr,
        ClassListColumn.name,
        ClassListColumn.motherName,
        ClassListColumn.dateOfBirth,
        ClassListColumn.aadhaar,
      ]);
      final labels = [l10n.reportSr, l10n.idGr, l10n.fieldName, l10n.reportMotherName, l10n.fieldDateOfBirth, l10n.idAadhaar];
      expect(d.columns.map((c) => c.label), labels);
      expect(d.tableForExport().header, labels);
      expect(data(d).first.cells, ['1', 'G1', 'Ayaan', 'Mother of Ayaan', '10/03/2009', '']);
    });

    test('Aadhaar is masked unless full numbers are asked for', () async {
      const layout = [ClassListColumn.serial, ClassListColumn.name, ClassListColumn.aadhaar];
      final masked = await reports.classList(divA, layout);
      final riya = data(masked)[1];
      expect(riya.cells[2], Aadhaar.mask(aadhaar.substring(8)));
      final everything = [for (final r in masked.rows) ...r.cells, ...masked.notes, masked.fileName].join(' ');
      expect(everything.replaceAll(' ', '').contains(aadhaar), isFalse);
      expect(masked.notes, contains(l10n.reportAadhaarMaskedNote));

      final full = await reports.classList(divA, layout, fullAadhaar: true);
      expect(data(full)[1].cells[2], Aadhaar.format(aadhaar));
      expect(full.notes, contains(l10n.reportAadhaarFullNote));
      expect(full.fileName, endsWith('-confidential'));
      expect(full.fileName.contains(aadhaar), isFalse);
    });

    test('girls only: filtered before counting, with the total of girls', () async {
      final d = await reports.studentMaster(
        show: const [ClassListColumn.serial, ClassListColumn.name, ClassListColumn.gender],
        gender: GenderFilter.girls,
        sort: StudentSort.name,
      );
      expect(data(d).map((r) => r.cells[1]), ['Riya', 'Zoya']);
      expect(d.notes.first, contains('${l10n.reportTotal} 2'));
      expect(d.notes.first, contains('${l10n.reportGirls} 2'));
      expect(d.notes.first, isNot(contains(l10n.reportBoys)));
    });

    test('sort by gender in a class list', () async {
      final d = await reports.classList(divA, StudentListLayout.classListDefault, sort: StudentSort.gender);
      expect(data(d).map((r) => r.cells[2]), ['Ayaan', 'Riya', 'Zoya']);
      final desc = await reports.classList(divA, StudentListLayout.classListDefault, sort: StudentSort.gender, descending: true);
      expect(data(desc).map((r) => r.cells[2]), ['Riya', 'Zoya', 'Ayaan']);
    });

    test('photo register: fixed columns, photos only when readable, PDF only', () async {
      final d = await reports.photoRegister(divA);
      expect(d.columns.map((c) => c.label), [
        l10n.reportSrNo,
        l10n.reportStudentName,
        l10n.reportMotherName,
        l10n.fieldDateOfBirth,
        l10n.reportPhoto,
      ]);
      expect(d.pdfOnly, isTrue);
      expect(d.landscape, isTrue);
      expect(d.imageColumns, {4});
      final rows = data(d);
      expect(rows[0].cells.take(4), ['1', 'Ayaan', 'Mother of Ayaan', '10/03/2009']);
      expect(rows[0].images[4], isNotNull);
      expect(rows[1].images, isEmpty); // no photo
      expect(rows[1].cells[4], l10n.reportNoPhoto);
      expect(rows[2].images, isEmpty); // damaged file: placeholder, no crash
    });

    test('the photo register renders as a multi-page PDF with photos', () async {
      final fonts = ReportFonts(
        ByteData.sublistView(File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync()),
        ByteData.sublistView(File('assets/fonts/NotoSans-Bold.ttf').readAsBytesSync()),
      );
      final one = await reports.photoRegister(divA);
      final many = one.copyWith(rows: [for (var i = 0; i < 20; i++) ...one.rows]);
      final bytes = await PdfReportRenderer.render(many, const ReportLetterhead(name: 'Test College'), fonts);
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      final text = latin1.decode(bytes);
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, greaterThanOrEqualTo(2));
    });
  });
}
