import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/validation/aadhaar.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/modules/students/import/import_fields.dart';
import 'package:shiksha_desk/modules/students/import/import_planner.dart';
import 'package:shiksha_desk/modules/students/import/import_repository.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

void main() {
  final aadhaar = '23456789012${Aadhaar.checkDigit('23456789012')}';

  test('typical school headings, English and Marathi, are recognised', () {
    final mapping = guessMapping([
      'Sr. No.', 'Name of Student', 'Father\'s Name', 'Surname', 'D.O.B.', 'Gender', 'GR No', 'Std', 'Div',
      'Roll No', 'Mobile No. (Father)', 'आधार क्रमांक', 'Remarks', 'Something else',
    ]);
    expect(mapping, [
      ImportField.serialNo, ImportField.fullName, ImportField.middleName, ImportField.lastName,
      ImportField.dateOfBirth, ImportField.gender, ImportField.grNumber, ImportField.className,
      ImportField.divisionName, ImportField.rollNumber, ImportField.mobile, ImportField.aadhaar,
      ImportField.notes, ImportField.ignore,
    ]);
  });

  test('the header row is found below a title row', () {
    final rows = [
      ['Greenfield College - Student List 2026-27', '', '', ''],
      ['', '', '', ''],
      ['Sr No', 'Student Name', 'GR No', 'Mobile'],
      ['1', 'Ayaan', 'G1', '9876543210'],
    ];
    expect(guessHeaderRow(rows), 2);
  });

  group('with a database', () {
    late StudentRepository students;
    late ImportRepository imports;
    late AcademicRepository academic;
    late ImportPlanner planner;
    final db = newMemoryDatabase();

    setUpAll(() async {
      await InstitutionCreator(db, testSession).create(
        profile: DemoData.organization,
        yearLabel: '2026-27',
        yearStart: DateTime(2026, 6, 1),
        yearEnd: DateTime(2027, 4, 30),
        template: StructureTemplate.juniorCollege,
        registry: buildModuleRegistry(),
      );
      students = StudentRepository(db, testSession, testCipher);
      academic = AcademicRepository(db, testSession);
      imports = ImportRepository(db, testSession, students, academic, AppSettingsRepository(db, testSession));
    });
    tearDownAll(() => db.close());

    Future<ImportPlanner> freshPlanner() async {
      final index = await students.importIndex();
      return ImportPlanner(
        academic: await academic.loadSnapshot(),
        existing: ExistingData(
          identifierOwners: index.identifierOwners,
          aadhaarOwners: index.aadhaarOwners,
          nameDob: index.nameDob,
          rollsByDivision: index.rollsByDivision,
        ),
        extraFields: const [],
        fingerprint: testCipher.fingerprint,
      );
    }

    final mapping = [
      'serialNo', 'fullName', 'gender', 'dateOfBirth', 'grNumber', 'className', 'divisionName', 'rollNumber',
      'mobile', 'aadhaar', 'bloodGroup',
    ];
    final sheet = [
      ['1', 'AYAAN SALIM SHAIKH', 'M', '14/03/2010', 'G-1', '11th Science', 'A', '1', '+91 98765 43210', aadhaar, 'B +ve'],
      ['2', 'Riya Suresh Patil', 'F', '31/02/2010', 'G-2', '11th Science', 'A', '2', '12345', '', 'O+'],
      ['3', '', 'M', '', 'G-3', '11th Science', 'A', '3', '', '', ''],
      ['4', 'Zoya Khan', 'F', '', 'G-1', '11th Science', 'A', '4', '', '', ''],
      ['5', 'Omkar More', 'M', '', 'G-5', '11th Science', 'A', '2', '', '', ''],
      ['6', 'Sana Mirza', 'F', '', 'G-6', '11th Vocational', 'B', '1', '', '', ''],
    ];

    test('rows are cleaned and checked before anything is saved', () async {
      planner = await freshPlanner();
      final plan = await planner.plan(sheet, mapping, ImportOptions());
      final r = plan.rows;

      expect(r[0].draft.firstName, 'Ayaan');
      expect(r[0].draft.middleName, 'Salim');
      expect(r[0].draft.lastName, 'Shaikh');
      expect(r[0].draft.gender, 'Male');
      expect(r[0].draft.dateOfBirth, DateTime(2010, 3, 14));
      expect(r[0].draft.bloodGroup, 'B+');
      expect(r[0].draft.guardians.single.mobile, '9876543210');
      expect(r[0].draft.identifiers[IdentifierType.aadhaar], aadhaar);
      expect(r[0].draft.divisionId, isNotNull);
      expect(r[0].severity, RowSeverity.ok);

      expect(r[1].issues.map((i) => i.code), containsAll([RowIssueCode.badDate, RowIssueCode.invalidMobile]));
      expect(r[1].severity, RowSeverity.warning);

      expect(r[2].issues.map((i) => i.code), contains(RowIssueCode.missingName));
      expect(r[3].issues.map((i) => i.code), contains(RowIssueCode.duplicateInFile));
      expect(r[4].issues.map((i) => i.code), contains(RowIssueCode.duplicateRoll));
      expect(r[5].issues.map((i) => i.code), contains(RowIssueCode.willCreatePlacement));
      expect(plan.missingPlacements, {('11th Vocational', 'B')});
    });

    test('importing saves good rows, creates the missing class, and records serial numbers', () async {
      planner = await freshPlanner();
      final plan = await planner.plan(sheet, mapping, ImportOptions());
      final result = await imports.commitStudents(
        plan: plan,
        options: ImportOptions(),
        sourceName: 'test.xlsx',
        extraFields: const [],
        activeYearId: (await academic.loadSnapshot()).activeYear!.id,
      );
      expect(result.added, 3);
      expect(result.skipped, 3);
      expect((await academic.listPrograms()).map((p) => p.name), contains('11th Vocational'));
      final serials = await imports.serialMap(result.batchId);
      expect(serials.keys, containsAll(['1', '2', '6']));

      // The same file again creates no duplicates.
      final again = await (await freshPlanner()).plan(sheet, mapping, ImportOptions());
      expect(again.rows[0].existingStudentId, isNotNull);
      final second = await imports.commitStudents(
        plan: again,
        options: ImportOptions(),
        sourceName: 'test.xlsx',
        extraFields: const [],
        activeYearId: (await academic.loadSnapshot()).activeYear!.id,
      );
      expect(second.added, 0);

      // Undo removes everything the first import added.
      await imports.undo(result.batchId);
      expect(await students.list(), isEmpty);
      expect((await imports.listBatches()).firstWhere((b) => b.id == result.batchId).undone, isTrue);
    });

    test('fill-empty updates only missing fields of existing students', () async {
      final id = await students.create(StudentDraft(
        firstName: 'Kabir',
        identifiers: {IdentifierType.grNumber: 'G-50'},
        bloodGroup: 'A+',
      ));
      final p = await (await freshPlanner()).plan(
        [
          ['Kabir Joshi', 'G-50', 'O-', '14/03/2010'],
        ],
        ['fullName', 'grNumber', 'bloodGroup', 'dateOfBirth'],
        ImportOptions(existing: ExistingPolicy.fillEmpty),
      );
      final result = await imports.commitStudents(
        plan: p,
        options: ImportOptions(existing: ExistingPolicy.fillEmpty),
        sourceName: 'update.csv',
        extraFields: const [],
        activeYearId: null,
      );
      expect(result.updated, 1);
      final d = (await students.load(id))!.draft;
      expect(d.bloodGroup, 'A+');
      // Dates are stored as plain calendar dates (in UTC), so compare the day itself.
      expect([d.dateOfBirth!.year, d.dateOfBirth!.month, d.dateOfBirth!.day], [2010, 3, 14]);
      expect(d.lastName, 'Joshi');
    });

    test('saved column matchings are kept per name', () async {
      await imports.saveTemplate(const ImportTemplate('College list', {'grno': 'grNumber'}));
      await imports.saveTemplate(const ImportTemplate('college list', {'grno': 'grNumber', 'std': 'className'}));
      final templates = await imports.templates();
      expect(templates, hasLength(1));
      expect(templates.single.columns['std'], 'className');
    });
  });
}
