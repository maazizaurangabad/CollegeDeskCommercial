import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/core/session/app_session.dart';
import 'package:shiksha_desk/platform/academic/academic_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/organization_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

Matcher refusedWith(AcademicIssue issue) =>
    throwsA(isA<AcademicValidationException>().having((e) => e.issue, 'issue', issue));

void main() {
  late AppDatabase db;
  late AcademicRepository repo;

  setUp(() async {
    db = newMemoryDatabase();
    await OrganizationRepository(db, testSession).create(DemoData.organization);
    repo = AcademicRepository(db, testSession);
  });
  tearDown(() => db.close());

  Future<String> addYear(String label, {bool active = false}) {
    final first = int.parse(label.substring(0, 4));
    return repo.addYear(
      label: label,
      startDate: DateTime(first, 6, 1),
      endDate: DateTime(first + 1, 4, 30),
      makeActive: active,
    );
  }

  test('only one academic year is active at a time', () async {
    final a = await addYear('2026-27', active: true);
    final b = await addYear('2027-28');
    await repo.setActiveYear(b);
    final years = await repo.listYears();
    expect(years.where((y) => y.isActive).map((y) => y.id), [b]);
    expect(years.firstWhere((y) => y.id == a).status, AcademicYearStatus.inactive);
    final org = await OrganizationRepository(db, testSession).loadActive();
    expect(org!.activeAcademicYear, '2027-28');
  });

  test('year rules: unique label, end after start, active year cannot be closed', () async {
    final a = await addYear('2026-27', active: true);
    await expectLater(() => addYear('2026-27'), refusedWith(AcademicIssue.duplicateYear));
    await expectLater(
() => repo.addYear(label: 'Bad', startDate: DateTime(2026, 6, 1), endDate: DateTime(2026, 5, 1)),
      refusedWith(AcademicIssue.endBeforeStart),
    );
    await expectLater(() => repo.closeYear(a), refusedWith(AcademicIssue.cannotCloseActiveYear));
  });

  test('a closed year cannot be made active or get new divisions', () async {
    await addYear('2026-27', active: true);
    final old = await addYear('2025-26');
    await repo.closeYear(old);
    final program = await repo.addProgram(name: '11th Science');
    await expectLater(() => repo.setActiveYear(old), refusedWith(AcademicIssue.yearIsClosed));
    await expectLater(
() => repo.addDivision(programId: program, academicYearId: old, name: 'A'),
      refusedWith(AcademicIssue.yearIsClosed),
    );
  });

  test('class and division names are unique where it matters', () async {
    final year = await addYear('2026-27', active: true);
    final program = await repo.addProgram(name: '11th Science');
    await expectLater(() => repo.addProgram(name: '11th science'), refusedWith(AcademicIssue.duplicateProgram));
    await repo.addDivision(programId: program, academicYearId: year, name: 'A');
    await expectLater(
() => repo.addDivision(programId: program, academicYearId: year, name: 'a'),
      refusedWith(AcademicIssue.duplicateDivision),
    );
    final other = await repo.addProgram(name: '12th Science');
    await repo.addDivision(programId: other, academicYearId: year, name: 'A');
    expect(await repo.listDivisions(year), hasLength(2));
  });

  test('a class with divisions cannot be deleted; an empty one can', () async {
    final year = await addYear('2026-27', active: true);
    final program = await repo.addProgram(name: '11th Science');
    final division = await repo.addDivision(programId: program, academicYearId: year, name: 'A');
    await expectLater(() => repo.deleteProgram(program), refusedWith(AcademicIssue.programHasDivisions));
    await repo.deleteDivision(division);
    await repo.deleteProgram(program);
    expect(await repo.listPrograms(), isEmpty);
    // The name can be used again after deletion.
    await repo.addProgram(name: '11th Science');
  });

  test('moving a class changes the order', () async {
    final a = await repo.addProgram(name: 'First');
    await repo.addProgram(name: 'Second');
    await repo.moveProgram(a, up: false);
    expect((await repo.listPrograms()).map((p) => p.name), ['Second', 'First']);
  });

  test('empty names are refused', () async {
    await expectLater(() => repo.addProgram(name: '   '), refusedWith(AcademicIssue.emptyName));
  });

  test('another institution sees none of these records', () async {
    await addYear('2026-27', active: true);
    await repo.addProgram(name: '11th Science');
    const other = AppSession(organizationId: 'org-other', deviceId: 'd', userId: 'u');
    final otherRepo = AcademicRepository(db, other);
    expect(await otherRepo.listYears(), isEmpty);
    expect(await otherRepo.listPrograms(), isEmpty);
  });

  test('the junior college template creates classes, divisions and promotion links', () async {
    final fresh = newMemoryDatabase();
    const session = AppSession(organizationId: 'org-new', deviceId: 'd', userId: 'u');
    await InstitutionCreator(fresh, session).create(
      profile: DemoData.organization,
      yearLabel: '2026-27',
      yearStart: DateTime(2026, 6, 1),
      yearEnd: DateTime(2027, 4, 30),
      template: StructureTemplate.juniorCollege,
      registry: buildModuleRegistry(),
    );
    final snapshot = await AcademicRepository(fresh, session).loadSnapshot();
    expect(snapshot.activeYear?.label, '2026-27');
    expect(snapshot.programs.map((p) => p.name), contains('11th Science'));
    expect(snapshot.divisions, hasLength(6));
    final eleventh = snapshot.programs.firstWhere((p) => p.name == '11th Science');
    final twelfth = snapshot.programs.firstWhere((p) => p.name == '12th Science');
    expect(eleventh.nextProgramId, twelfth.id);
    expect(twelfth.nextProgramId, isNull);
    await fresh.close();
  });
}
