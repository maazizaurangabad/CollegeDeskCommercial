import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/modules/fees/data/fee_repository.dart';
import 'package:shiksha_desk/modules/results/data/result_repository.dart';
import 'package:shiksha_desk/modules/results/domain/result_models.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/modules/students/promotion/promotion_models.dart';
import 'package:shiksha_desk/modules/students/promotion/promotion_repository.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

PromotionCandidate _c(String id, String name, {String? gr, int? roll}) => PromotionCandidate(
      studentId: id,
      name: name,
      grNumber: gr,
      roll: roll,
      fromDivisionId: 'd',
      fromProgramId: 'p',
      divisionName: 'A',
      nextProgramId: 'q',
      action: PromotionAction.promote,
    );

void main() {
  test('standard rules: pass and ATKT move up, fail repeats, last class leaves', () {
    expect(suggestedAction(result: ResultStatus.passed, hasNext: true), PromotionAction.promote);
    expect(suggestedAction(result: ResultStatus.atkt, hasNext: true), PromotionAction.promote);
    expect(suggestedAction(result: ResultStatus.atkt, hasNext: true, promoteAtkt: false), PromotionAction.repeat);
    expect(suggestedAction(result: ResultStatus.failed, hasNext: true), PromotionAction.repeat);
    expect(suggestedAction(result: ResultStatus.failed, hasNext: false), PromotionAction.repeat);
    expect(suggestedAction(result: ResultStatus.passed, hasNext: false), PromotionAction.leave);
    // No result yet: moves up (flagged on screen); in the last class it waits.
    expect(suggestedAction(result: null, hasNext: true), PromotionAction.promote);
    expect(suggestedAction(result: null, hasNext: false), PromotionAction.skip);
  });

  test('roll numbers continue after those already used in the new class', () {
    final joining = [_c('z', 'Zoya', gr: '20', roll: 1), _c('a', 'Ayaan', gr: '30', roll: 5), _c('r', 'Riya', gr: '10', roll: 2)];
    expect(assignRolls(joining, order: RollOrder.byName, taken: {1, 2}), {'a': 3, 'r': 4, 'z': 5});
    expect(assignRolls(joining, order: RollOrder.byGr), {'r': 1, 'z': 2, 'a': 3});
    // Keep: old roll when free, the next free one otherwise.
    expect(assignRolls(joining, order: RollOrder.keep, taken: {2}), {'z': 1, 'a': 5, 'r': 6});
  });

  test('promotion moves, repeats and graduates students; last year keeps its records; undo restores', () async {
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
    final academic = AcademicRepository(db, testSession);
    final settings = AppSettingsRepository(db, testSession);
    final students = StudentRepository(db, testSession, testCipher);
    final results = ResultRepository(db, testSession, settings, students);
    final fees = FeeRepository(db, testSession, settings, students);
    final promotion = PromotionRepository(db, testSession, students, academic, results, fees);

    final snapshot = await academic.loadSnapshot();
    final thisYear = snapshot.activeYear!.id;
    final programs = {for (final p in snapshot.programs) p.name: p.id};
    String div(String program) => snapshot.divisions.firstWhere((d) => d.programId == programs[program]).id;
    final nextYear = await academic.addYear(label: '2027-28', startDate: DateTime(2027, 6, 1), endDate: DateTime(2028, 4, 30));

    Future<String> add(String name, String program, int roll) =>
        students.create(StudentDraft(firstName: name, lastName: 'Shaikh', divisionId: div(program), rollNumber: roll));
    final zoya = await add('Zoya', '11th Science', 1);
    final ayaan = await add('Ayaan', '11th Science', 2);
    final riya = await add('Riya', '11th Science', 3);
    final imran = await add('Imran', '12th Science', 1);

    final list = await promotion.candidates(fromYearId: thisYear, toYearId: nextYear);
    expect(list, hasLength(4));
    PromotionCandidate of(String id) => list.firstWhere((c) => c.studentId == id);
    // No results entered: 11th moves up (flagged), 12th waits.
    expect(of(ayaan).action, PromotionAction.promote);
    expect(of(ayaan).noResult, isTrue);
    expect(of(imran).action, PromotionAction.skip);
    of(riya).action = PromotionAction.repeat;
    of(imran).action = PromotionAction.leave;

    final done = await promotion.commit(
      fromYearId: thisYear,
      toYearId: nextYear,
      candidates: list,
      leaveReason: 'Passed HSC',
      copyFees: false,
    );
    expect([done.promoted, done.repeated, done.left, done.skipped], [2, 1, 1, 0]);

    // Next year: 12th Science A created, new rolls by name; Riya again in 11th.
    final next = {for (final s in await students.list(academicYearId: nextYear)) s.id: s};
    final nextDivisions = await academic.listDivisions(nextYear);
    String nameOf(String? divisionId) {
      final d = nextDivisions.firstWhere((d) => d.id == divisionId);
      return '${snapshot.programs.firstWhere((p) => p.id == d.programId).name} ${d.name}';
    }

    expect(nameOf(next[ayaan]!.divisionId), '12th Science A');
    expect([next[ayaan]!.rollNumber, next[zoya]!.rollNumber], [1, 2]);
    expect(nameOf(next[riya]!.divisionId), '11th Science A');
    expect(next[imran]!.divisionId, isNull);
    final imranNow = (await students.load(imran))!;
    expect(imranNow.status, StudentStatus.left);
    expect(imranNow.leavingReason, 'Passed HSC');

    // Last year still has its class (results, lists and fees of that year).
    final roster = await results.roster(div('11th Science'), thisYear);
    expect(roster.map((r) => r.id), containsAll([zoya, ayaan, riya]));
    final last = {for (final s in await students.list(academicYearId: thisYear)) s.id: s};
    expect(last[ayaan]!.divisionId, div('11th Science'));

    // Nobody is offered twice.
    expect(await promotion.candidates(fromYearId: thisYear, toYearId: nextYear), isEmpty);

    // Undo: everyone back as before.
    await promotion.undo(done.batchId);
    final back = {for (final s in await students.list(academicYearId: nextYear)) s.id: s};
    expect(back[ayaan]?.divisionId, isNull);
    final again = {for (final s in await students.list(academicYearId: thisYear)) s.id: s};
    expect(again[ayaan]!.divisionId, div('11th Science'));
    expect((await students.load(imran))!.status, StudentStatus.active);
    expect((await promotion.history()).single.undone, isTrue);
    expect(await promotion.candidates(fromYearId: thisYear, toYearId: nextYear), hasLength(4));
  });
}
