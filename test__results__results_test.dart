import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/l10n/gen/app_localizations_en.dart';
import 'package:shiksha_desk/modules/results/application/results_providers.dart';
import 'package:shiksha_desk/modules/results/data/result_repository.dart';
import 'package:shiksha_desk/modules/results/domain/result_models.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

Subject _s(String id, String name, {String? column, bool grade = false, int order = 10}) => Subject(
      id: id,
      programId: 'p',
      name: name,
      columnName: column ?? name,
      displayOrder: order,
      isGrade: grade,
      maxMarks: grade ? 0 : 100,
      passMarks: grade ? 0 : 35,
    );

void main() {
  group('result calculator', () {
    final subjects = [
      _s('eng', 'English', order: 10),
      _s('urd', 'Urdu', column: 'Urdu/Hindi', order: 20),
      _s('hin', 'Hindi', column: 'Urdu/Hindi', order: 20),
      _s('evs', 'Env. Sci.', grade: true, order: 5),
      _s('phy', 'Physics', order: 30),
    ];
    final columns = SubjectColumn.of(subjects);
    final roster = <RosterStudent>[
      (id: 'a', name: 'Ayaan', roll: 1, gr: '1246'),
      (id: 'b', name: 'Bilal', roll: 2, gr: '1247'),
      (id: 'c', name: 'Chand', roll: 3, gr: null),
      (id: 'd', name: 'Danish', roll: 4, gr: null),
    ];
    const m = MarkEntry.new;
    final marks = {
      'e2': {
        'a': {'eng': m(marks: 52), 'urd': m(marks: 54), 'phy': m(marks: 50), 'evs': m(grade: 'A')},
        'b': {'eng': m(marks: 30), 'hin': m(marks: 70), 'phy': m(marks: 60)},
        'c': {'eng': m(absent: true), 'urd': m(marks: 60)},
        'd': {'eng': m(marks: 80), 'urd': m(marks: 70), 'phy': m(marks: 6)},
      },
      'e1': {
        'a': {'eng': m(marks: 40), 'urd': m(marks: 40), 'phy': m(marks: 40)},
      },
    };

    test('columns: choices share one column, grade subjects come last', () {
      expect(columns.map((c) => c.name), ['English', 'Urdu/Hindi', 'Physics', 'Env. Sci.']);
      expect(columns[1].isChoice, isTrue);
      expect(columns.last.isGrade, isTrue);
    });

    test('pass, fail, incomplete, choices from marks, grades not in total, ranks', () {
      final r = ResultCalculator.compute(
        roster: roster,
        columns: columns,
        examIds: ['e2'],
        marks: marks,
        choices: const {},
        rules: const ResultRules(),
      );
      final a = r[0], b = r[1], c = r[2], d = r[3];
      expect(a.total, 156);
      expect(a.maxTotal, 300);
      expect(const ResultRules().percentText(a.percent), '52');
      expect(a.status, ResultStatus.passed);
      expect(a.resultClass, ResultClass.second);
      expect(a.columns['Urdu/Hindi']!.subject!.name, 'Urdu');
      expect(a.columns['Env. Sci.']!.text, 'A');
      expect(a.rank, 1);

      expect(b.columns['Urdu/Hindi']!.subject!.name, 'Hindi');
      expect(b.status, ResultStatus.failed);
      expect(b.failedSubjects, 1);
      expect(b.columns['English']!.passed, isFalse);
      expect(b.rank, isNull);

      expect(c.status, ResultStatus.incomplete); // Physics not entered
      expect(c.columns['English']!.text, 'AB');
      expect(d.status, ResultStatus.failed);
    });

    test('ATKT when allowed, and the final result adds the counted exams', () {
      final atkt = ResultCalculator.compute(
        roster: roster,
        columns: columns,
        examIds: ['e2'],
        marks: marks,
        choices: const {},
        rules: const ResultRules(atktSubjects: 1),
      );
      expect(atkt[1].status, ResultStatus.atkt);

      final both = ResultCalculator.compute(
        roster: roster.sublist(0, 1),
        columns: columns,
        examIds: ['e1', 'e2'],
        marks: marks,
        choices: const {},
        rules: const ResultRules(wholePercent: false),
      );
      expect(both.single.total, 276);
      expect(both.single.maxTotal, 600);
      expect(const ResultRules(wholePercent: false).percentText(both.single.percent), '46.00');
      expect(both.single.status, ResultStatus.passed); // 92 out of 200 in each, pass needs 70
    });

    test('equal totals share a rank', () {
      final list = ResultCalculator.rank([
        for (final (id, total) in [('x', 300), ('y', 280), ('z', 300), ('w', 250)])
          StudentResult(
            studentId: id,
            name: id,
            columns: const {},
            total: total,
            maxTotal: 300,
            status: ResultStatus.passed,
            failedSubjects: 0,
          ),
      ]);
      expect(list.map((r) => r.rank), [1, 3, 1, 4]);
    });

    test('typed values are read as marks, absent or grade', () {
      final eng = subjects.first;
      final evs = subjects[3];
      expect(ResultRepository.parse(' 56 ', eng)!.marks, 56);
      expect(ResultRepository.parse('ab', eng)!.absent, isTrue);
      expect(ResultRepository.parse('', eng), isNull);
      expect(ResultRepository.parse('b', evs)!.grade, 'B');
      expect(() => ResultRepository.parse('101', eng),
          throwsA(isA<ResultException>().having((e) => e.issue, 'issue', ResultIssue.overMax)));
      expect(() => ResultRepository.parse('x1', eng), throwsA(isA<ResultException>()));
    });
  });

  group('results storage', () {
    late AppDatabase db;
    late ResultRepository results;
    late String yearId;
    late String programId;
    late String divisionId;
    late List<String> ids;

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
      yearId = academic.activeYear!.id;
      final division = academic.divisions.first;
      divisionId = division.id;
      programId = division.programId;
      final students = StudentRepository(db, testSession, testCipher);
      ids = [
        for (final (i, name) in ['Ayaan', 'Rehan'].indexed)
          await students.create(StudentDraft(
            firstName: name,
            lastName: 'Shaikh',
            divisionId: division.id,
            rollNumber: i + 1,
            admissionDate: DateTime(2026, 6, 15),
            identifiers: {IdentifierType.grNumber: '${1246 + i}'},
          )),
      ];
      results = ResultRepository(db, testSession, AppSettingsRepository(db, testSession), students);
    });
    tearDown(() => db.close());

    test('1st and 2nd Term are added once; only the 2nd Term counts in the final result', () async {
      final exams = await results.exams(yearId);
      expect(exams.map((e) => e.name), ResultRepository.defaultExams);
      expect(exams.map((e) => e.countsInFinal), [false, true]);
      expect(await results.exams(yearId), hasLength(2));
      await expectLater(results.addExam(yearId, '1st term examination'),
          throwsA(isA<ResultException>().having((e) => e.issue, 'issue', ResultIssue.duplicate)));
    });

    test('marks, choices and the class result sheet', () async {
      expect(await results.addScienceTemplate(programId), 11);
      expect(await results.addScienceTemplate(programId), 0);
      final subjects = await results.subjects(programId: programId);
      final columns = SubjectColumn.of(subjects);
      expect(columns.map((c) => c.name),
          ['English', 'Urdu/Arabic/Hindi', 'Physics', 'Chemistry', 'Biology', 'Maths/Socio', 'Env. Sci.', 'Phy. Edu.']);
      String id(String name) => subjects.firstWhere((s) => s.name == name).id;

      final term2 = (await results.exams(yearId)).last.id;
      await results.setChoice(academicYearId: yearId, studentIds: ids, columnName: 'Urdu/Arabic/Hindi', subjectId: id('Urdu'));
      await results.setChoice(academicYearId: yearId, studentIds: [ids[1]], columnName: 'Maths/Socio', subjectId: id('Sociology'));
      await results.setChoice(academicYearId: yearId, studentIds: [ids[0]], columnName: 'Maths/Socio', subjectId: id('Mathematics'));

      final roster = await results.roster(divisionId, yearId);
      expect(roster.map((r) => r.gr), ['1246', '1247']);

      final saved = await results.saveMarks(term2, {
        ids[0]: {
          id('English'): const MarkEntry(marks: 52),
          id('Urdu'): const MarkEntry(marks: 54),
          id('Physics'): const MarkEntry(marks: 50),
          id('Chemistry'): const MarkEntry(marks: 50),
          id('Biology'): const MarkEntry(marks: 55),
          id('Mathematics'): const MarkEntry(marks: 51),
          id('Env. Sci.'): const MarkEntry(grade: 'A'),
          id('Phy. Edu.'): const MarkEntry(grade: 'B'),
        },
        ids[1]: {
          id('English'): const MarkEntry(marks: 59),
          id('Urdu'): const MarkEntry(marks: 70),
          id('Physics'): const MarkEntry(marks: 60),
          id('Chemistry'): const MarkEntry(marks: 68),
          id('Biology'): const MarkEntry(marks: 57),
          id('Sociology'): const MarkEntry(marks: 20),
        },
      });
      expect(saved, 14);
      // Saving the same again changes nothing; clearing removes one.
      expect(await results.saveMarks(term2, {ids[0]: {id('English'): const MarkEntry(marks: 52)}}), 0);

      final r = await results.classResult(divisionId: divisionId, programId: programId, academicYearId: yearId);
      final ayaan = r.results.firstWhere((x) => x.studentId == ids[0]);
      expect(ayaan.total, 312);
      expect(ayaan.status, ResultStatus.passed);
      final rehan = r.results.firstWhere((x) => x.studentId == ids[1]);
      expect(rehan.columns['Maths/Socio']!.subject!.name, 'Sociology');
      expect(rehan.status, ResultStatus.failed);

      final sheet = resultSheetDataset(
        AppLocalizationsEn(),
        title: 'Final result',
        classLabel: '11th Science A',
        yearLabel: '2026-27',
        columns: r.columns,
        results: r.results,
        rules: await results.rules(),
      );
      expect(sheet.columns.map((c) => c.label).take(4), ['Sr', 'G.R. No', 'Name of student', 'English']);
      expect(sheet.rows.first.cells.sublist(9, 14), ['312', '52', 'A', 'B', 'PASSED']);
      expect(sheet.rows[1].cells.last, 'FAILED');

      await expectLater(results.deleteSubject(id('English')),
          throwsA(isA<ResultException>().having((e) => e.issue, 'issue', ResultIssue.inUse)));
      await results.deleteSubject(id('Arabic'));
      await expectLater(results.deleteExam(term2), throwsA(isA<ResultException>()));
    });

    test('rules are kept in settings', () async {
      await results.saveRules(const ResultRules(wholePercent: false, atktSubjects: 2, distinction: 70));
      final r = await results.rules();
      expect(r.wholePercent, isFalse);
      expect(r.atktSubjects, 2);
      expect(r.distinction, 70);
      expect(r.firstClass, 60);
    });

    test('final result of one student (also after leaving) and the class analysis', () async {
      await results.addScienceTemplate(programId);
      final subjects = await results.subjects(programId: programId);
      String id(String name) => subjects.firstWhere((s) => s.name == name).id;
      final term2 = (await results.exams(yearId)).last.id;
      await results.saveMarks(term2, {
        for (final (i, st) in ids.indexed)
          st: {
            id('English'): MarkEntry(marks: 60 + i * 10),
            id('Urdu'): const MarkEntry(marks: 70),
            id('Physics'): const MarkEntry(marks: 65),
            id('Chemistry'): const MarkEntry(marks: 66),
            id('Biology'): const MarkEntry(marks: 67),
            id('Mathematics'): const MarkEntry(marks: 68),
          },
      });
      final f = await results.finalResultOf(ids[0]);
      expect(f, isNotNull);
      expect(f!.result.total, 396);
      expect(f.result.status, ResultStatus.passed);
      expect(f.exams.single.name, '2nd Term Examination');
      expect(f.yearLabel, '2026-27');

      await StudentRepository(db, testSession, testCipher).markLeft(ids[0], date: DateTime(2027, 4, 30), reason: 'Passed');
      expect((await results.finalResultOf(ids[0]))!.result.total, 396);

      final r = await results.classResult(divisionId: divisionId, programId: programId, academicYearId: yearId);
      final analysis = resultAnalysisDataset(
        AppLocalizationsEn(),
        title: 'Final result',
        classLabel: '11th Science A',
        yearLabel: '2026-27',
        columns: r.columns,
        results: r.results,
        rules: await results.rules(),
      );
      // Ayaan has left, so only Rehan is in the class now.
      expect(analysis.rows.first.cells.sublist(1, 8), ['English', '1', '1', '0', '100.0', '70', '70.0']);
      expect(analysis.notes.first, contains('1. Rehan Shaikh'));
    });
  });
}
