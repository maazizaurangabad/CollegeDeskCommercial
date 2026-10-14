import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/core/files/xlsx_styled.dart';
import 'package:shiksha_desk/core/validation/date_words.dart';
import 'package:shiksha_desk/modules/certificates/application/certificate_pdf.dart';
import 'package:shiksha_desk/modules/certificates/data/certificate_repository.dart';
import 'package:shiksha_desk/modules/certificates/domain/certificate_models.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/reporting/pdf_report_renderer.dart';
import 'package:shiksha_desk/platform/reporting/report_dataset.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

void main() {
  test('dates are written in words the way certificates need', () {
    expect(DateWords.date(DateTime(2010, 3, 14)), 'Fourteenth March Two Thousand Ten');
    expect(DateWords.date(DateTime(2009, 12, 1)), 'First December Two Thousand Nine');
    expect(DateWords.date(DateTime(2000, 1, 31)), 'Thirty First January Two Thousand');
    expect(DateWords.year(1998), 'Nineteen Hundred Ninety Eight');
    expect(DateWords.date(DateTime(2011, 8, 22)), 'Twenty Second August Two Thousand Eleven');
  });

  group('certificates', () {
    late AppDatabase db;
    late StudentRepository students;
    late CertificateRepository certs;
    late Map<String, String> labels;
    late String studentId;

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
      final academic = await academicRepo.loadSnapshot();
      labels = await academicRepo.divisionLabels();
      students = StudentRepository(db, testSession, testCipher);
      studentId = await students.create(StudentDraft(
        firstName: 'Ayaan',
        middleName: 'Salim',
        lastName: 'Shaikh',
        gender: 'Male',
        dateOfBirth: DateTime(2010, 3, 14),
        caste: 'Example',
        subCaste: 'Sub',
        admissionDate: DateTime(2026, 6, 15),
        divisionId: academic.divisions.first.id,
        rollNumber: 7,
        identifiers: {IdentifierType.grNumber: '4512'},
        guardians: [GuardianDraft(name: 'Shabana Shaikh', relation: 'Mother', mobile: '9876543210', isPrimary: true)],
      ));
      certs = CertificateRepository(db, testSession, students, clock: () => DateTime(2026, 10, 14));
    });
    tearDown(() => db.close());

    test('details are filled in from the student record', () async {
      final f = await certs.prefill(studentId, divisionLabels: labels);
      expect(f[CertField.name], 'Ayaan Salim Shaikh');
      expect(f[CertField.motherName], 'Shabana Shaikh');
      expect(f[CertField.grNumber], '4512');
      expect(f[CertField.dateOfBirth], '14/03/2010');
      expect(f[CertField.dateOfBirthWords], 'Fourteenth March Two Thousand Ten');
      expect(f[CertField.casteSubcaste], 'Example - Sub');
      expect(f[CertField.academicYear], '2026-27');
      expect(f[CertField.className], isNotEmpty);
    });

    test('numbers run per type and year and are never reused, even after cancelling', () async {
      final f = await certs.prefill(studentId, divisionLabels: labels);
      final a = await certs.issue(kind: CertificateKind.bonafide, studentId: studentId, fields: f, academicYearLabel: '2026-27');
      final b = await certs.issue(kind: CertificateKind.bonafide, studentId: studentId, fields: f, academicYearLabel: '2026-27');
      final n = await certs.issue(kind: CertificateKind.noc, studentId: studentId, fields: f, academicYearLabel: '2026-27');
      expect(a.serialLabel, 'BON/2026-27/0001');
      expect(b.serialLabel, 'BON/2026-27/0002');
      expect(n.serialLabel, 'NOC/2026-27/0001');
      await certs.cancel(b.id, 'Wrong purpose');
      final c = await certs.issue(kind: CertificateKind.bonafide, studentId: studentId, fields: f, academicYearLabel: '2026-27');
      expect(c.serialLabel, 'BON/2026-27/0003');
      final next = await certs.issue(kind: CertificateKind.bonafide, studentId: studentId, fields: f, academicYearLabel: '2027-28');
      expect(next.serialLabel, 'BON/2027-28/0001');
      final register = await certs.list(kind: CertificateKind.bonafide);
      expect(register.where((r) => r.status == CertificateStatus.cancelled).single.cancelReason, 'Wrong purpose');
    });

    test('a leaving certificate marks the student as left; a second one is a duplicate with the same number', () async {
      final f = await certs.prefill(studentId, divisionLabels: labels);
      f[CertField.leavingDate] = '10/10/2026';
      f[CertField.leavingReason] = 'Parents transferred';
      final lc = await certs.issue(
        kind: CertificateKind.leaving,
        studentId: studentId,
        fields: f,
        academicYearLabel: '2026-27',
        markLeft: true,
      );
      expect(lc.serialLabel, 'LC/2026-27/0001');
      final detail = await students.load(studentId);
      expect(detail!.status, StudentStatus.left);
      expect(detail.leavingReason, 'Parents transferred');

      final dup = await certs.issue(kind: CertificateKind.leaving, studentId: studentId, fields: f, academicYearLabel: '2026-27');
      expect(dup.isDuplicate, isTrue);
      expect(dup.serialLabel, lc.serialLabel);

      await certs.recordPrint(dup.id);
      await certs.recordPrint(dup.id);
      expect((await certs.get(dup.id))!.printCount, 2);
    });

    test('every certificate type renders to a PDF', () async {
      final fonts = ReportFonts(
        ByteData.sublistView(File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync()),
        ByteData.sublistView(File('assets/fonts/NotoSans-Bold.ttf').readAsBytesSync()),
      );
      final f = await certs.prefill(studentId, divisionLabels: labels);
      for (final kind in CertificateKind.values) {
        final bytes = await CertificatePdf.build(
          kind: kind,
          f: f,
          serialLabel: '${kind.prefix}/2026-27/0001',
          issuedOn: DateTime(2026, 10, 14),
          head: const ReportLetterhead(name: 'Test College', lines: ['Address']),
          fonts: fonts,
          institutionWord: 'junior college',
          duplicate: kind == CertificateKind.leaving,
        );
        expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-', reason: kind.name);
      }
    });
  });

  test('lists can be filtered and sorted, with Boys / Girls counts per group', () {
    const labels = ReportCountLabels(total: 'Total', byValue: {'Male': 'Boys', 'Female': 'Girls'});
    final data = ReportDataset(
      title: 'List',
      fileName: 'list',
      columns: const [ReportColumn('Roll'), ReportColumn('Name'), ReportColumn('Gender')],
      rows: const [
        ReportRow.group('11th A'),
        ReportRow(['2', 'Riya', 'Female']),
        ReportRow(['1', 'Ayaan', 'Male']),
        ReportRow.group('11th B'),
        ReportRow(['1', 'Zoya', 'Female']),
      ],
      countColumn: 2,
      countLabels: labels,
      filterColumns: const {2},
    ).withCounts();
    expect(data.rows.first.groupTitle, '11th A   (Total 2 · Boys 1 · Girls 1)');
    expect(data.notes.first, 'Total 3 · Boys 1 · Girls 2');

    final sorted = data.arranged(sortColumn: 0);
    expect(sorted.rows.where((r) => r.kind == ReportRowKind.data).map((r) => r.cells[1]), ['Ayaan', 'Riya', 'Zoya']);

    final boys = data.arranged(filters: {2: 'Male'});
    expect(boys.rows.where((r) => r.kind == ReportRowKind.group), hasLength(1));
    expect(boys.notes.first, 'Total 1 · Boys 1');

    final export = data.tableForExport();
    expect(export.header, ['Group', 'Roll', 'Name', 'Gender']);
    expect(export.rows.first, ['11th A', '2', 'Riya', 'Female']);
  });

  test('the formatted Excel file has a frozen header, filter buttons, real numbers and dates', () {
    final bytes = XlsxStyledWriter.write(
      sheetName: 'Class list',
      headingLines: ['Test College', 'Class list'],
      header: ['Roll', 'Name', 'Date of birth'],
      rows: [
        ['1', 'Ayaan', '14/03/2010'],
        ['2', 'Riya', '01/01/2010'],
      ],
      types: [XlsxCellType.number, XlsxCellType.text, XlsxCellType.date],
      notes: ['Total 2'],
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheet = utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(sheet, contains('<autoFilter ref="A4:C6"/>'));
    expect(sheet, contains('state="frozen"'));
    expect(sheet, contains('<v>1</v>'));
    expect(sheet, contains('<v>40251</v>'));
    final workbook = utf8.decode(archive.findFile('xl/workbook.xml')!.content as List<int>);
    expect(workbook, contains('_xlnm.Print_Titles'));
  });
}
