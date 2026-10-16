import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/validation/aadhaar.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/modules/students/import/import_planner.dart';
import 'package:shiksha_desk/modules/students/import/import_report.dart';
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

  test('Aadhaar cells are masked to the last four digits', () {
    expect(maskAadhaarCell('2345 6789 0123'), 'XXXX XXXX 0123');
    expect(maskAadhaarCell('12'), 'XXXX');
    expect(maskAadhaarCell('not given'), 'XXXX');
    expect(maskAadhaarCell('  '), '');
  });

  test('every row is accounted for: skipped, already saved, duplicate, warnings, saved', () async {
    final db = newMemoryDatabase();
    addTearDown(db.close);
    await InstitutionCreator(db, testSession).create(
      profile: DemoData.organization,
      yearLabel: '2026-27',
      yearStart: DateTime(2026, 6, 1),
      yearEnd: DateTime(2027, 4, 30),
      template: StructureTemplate.juniorCollege,
      registry: buildModuleRegistry(),
    );
    final students = StudentRepository(db, testSession, testCipher);
    final academic = AcademicRepository(db, testSession);
    final imports = ImportRepository(db, testSession, students, academic, AppSettingsRepository(db, testSession));
    await students.create(StudentDraft(firstName: 'Kabir', lastName: 'Joshi', identifiers: {IdentifierType.grNumber: 'G-50'}));
    await students.create(StudentDraft(firstName: 'Sana', lastName: 'Mirza', dateOfBirth: DateTime(2010, 5, 1)));

    final index = await students.importIndex();
    final planner = ImportPlanner(
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
    const headers = ['Name', 'GR No', 'Mother', 'DOB', 'Mobile', 'Aadhaar'];
    const mapping = ['fullName', 'grNumber', 'motherName', 'dateOfBirth', 'mobile', 'aadhaar'];
    final sheet = [
      ['Ayaan Shaikh', 'G-1', 'Rukhsana', '14/03/2010', '9876543210', aadhaar], // saved
      ['', 'G-2', 'Mother', '14/03/2010', '', ''], // no name: skipped
      ['Kabir Joshi', 'G-50', 'Mother', '', '', ''], // already in the app
      ['Sana Mirza', 'G-3', 'Mother', '01/05/2010', '', ''], // same name and DOB
      ['Riya Patil', 'G-4', 'Mother', '14/03/2010', '12345', ''], // bad mobile: saved with a warning
    ];
    final options = ImportOptions();
    final plan = await planner.plan(sheet, mapping, options);
    final result = await imports.commitStudents(
      plan: plan,
      options: options,
      sourceName: 'admissions.xlsx',
      extraFields: const [],
      activeYearId: null,
    );
    final report = ImportReport.from(plan: plan, result: result, sourceName: 'admissions.xlsx', headers: headers, mapping: mapping);

    expect(report.total, 5);
    expect(report.added, result.added);
    expect(report.added, 3);
    expect(report.entries.map((e) => e.kind), [
      ImportRowKind.saved,
      ImportRowKind.skipped,
      ImportRowKind.alreadySaved,
      ImportRowKind.possibleDuplicate,
      ImportRowKind.savedWithWarnings,
    ]);
    expect(report.notSaved, 2);
    expect(report.entries[0].problems, isEmpty);

    final skipped = report.of(ImportRowKind.skipped).single;
    expect(skipped.rowNumber, 3); // the sheet's own row (header is row 1)
    expect(skipped.problems.map((i) => i.code), contains(RowIssueCode.missingName));
    expect(skipped.studentId, isNull);

    final existing = report.of(ImportRowKind.alreadySaved).single;
    expect(existing.studentId, isNotNull);
    expect(existing.problems.map((i) => i.code), contains(RowIssueCode.alreadyExists));

    // The original cells, Aadhaar masked; and the download has the reason.
    final cells = report.sourceOf(report.entries[0]);
    expect(cells.last, ('Aadhaar', Aadhaar.mask(aadhaar.substring(8))));
    final table = report.exportTable(
      report.entries,
      kindLabel: (k) => k.name,
      issueLabel: (i) => i.code.name,
      fixLabel: (c) => 'fix ${c.name}',
      leadingHeaders: const ['Excel row', 'Status', 'Reason', 'What to do'],
    );
    expect(table.header, ['Excel row', 'Status', 'Reason', 'What to do', ...headers]);
    expect(table.rows[1].take(4), ['3', 'skipped', contains('missingName'), contains('fix missingName')]);
    expect(table.rows.expand((r) => r).join(' ').replaceAll(' ', '').contains(aadhaar), isFalse);

    // Added by hand later: remembered, nothing else changes.
    final after = report.markResolved(3);
    expect(after.resolved, {3});
    expect(after.count(ImportRowKind.skipped), 1);
  });
}
