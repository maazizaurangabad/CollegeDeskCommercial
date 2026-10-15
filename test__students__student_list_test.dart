import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/modules/students/presentation/student_picker.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

StudentListItem _item(String name, {int? roll, String? gr, String code = 'S1'}) => StudentListItem(
      id: name,
      displayCode: code,
      fullName: name,
      status: StudentStatus.active,
      rollNumber: roll,
      grNumber: gr,
    );

void main() {
  test('G.R. numbers and codes sort as numbers (9 before 10)', () {
    expect(compareNatural('9', '10'), lessThan(0));
    expect(compareNatural('GR-9', 'GR-10'), lessThan(0));
    expect(compareNatural('', '5'), greaterThan(0));
  });

  test('students sort by roll, G.R., name or code', () {
    final items = [
      _item('Zoya', roll: 2, gr: '1250', code: 'S10'),
      _item('Aisha', roll: 3, gr: '998', code: 'S9'),
      _item('Imran', roll: 1, gr: null, code: 'S11'),
    ];
    expect(sortStudents(items, StudentSort.roll).map((s) => s.fullName), ['Imran', 'Zoya', 'Aisha']);
    expect(sortStudents(items, StudentSort.gr).map((s) => s.fullName), ['Aisha', 'Zoya', 'Imran']);
    expect(sortStudents(items, StudentSort.name).map((s) => s.fullName), ['Aisha', 'Imran', 'Zoya']);
    expect(sortStudents(items, StudentSort.code).map((s) => s.fullName), ['Aisha', 'Zoya', 'Imran']);
  });

  test('the list carries G.R. numbers; several students can be marked left or moved to the bin', () async {
    final AppDatabase db = newMemoryDatabase();
    addTearDown(db.close);
    await InstitutionCreator(db, testSession).create(
      profile: DemoData.organization,
      yearLabel: '2026-27',
      yearStart: DateTime(2026, 6, 1),
      yearEnd: DateTime(2027, 4, 30),
      template: StructureTemplate.juniorCollege,
      registry: buildModuleRegistry(),
    );
    final academic = await AcademicRepository(db, testSession).loadSnapshot();
    final repo = StudentRepository(db, testSession, testCipher);
    final ids = [
      for (var i = 0; i < 4; i++)
        await repo.create(StudentDraft(
          firstName: 'Student$i',
          lastName: 'Shaikh',
          divisionId: academic.divisions.first.id,
          rollNumber: i + 1,
          admissionDate: DateTime(2026, 6, 15),
          identifiers: {IdentifierType.grNumber: '${5001 + i}'},
        )),
    ];
    final list = await repo.list(academicYearId: academic.activeYear!.id);
    expect(list.map((s) => s.grNumber).toSet(), {'5001', '5002', '5003', '5004'});

    expect(await repo.markManyLeft(ids.take(2), date: DateTime(2026, 10, 1), reason: 'Transfer'), 2);
    expect(await repo.moveManyToRecycleBin(ids.skip(3)), 1);
    final after = await repo.list(academicYearId: academic.activeYear!.id);
    expect(after, hasLength(3));
    expect(after.where((s) => s.status == StudentStatus.left), hasLength(2));
  });
}
