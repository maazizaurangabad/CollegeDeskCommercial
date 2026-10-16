import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/core/validation/aadhaar.dart';
import 'package:shiksha_desk/l10n/gen/app_localizations_en.dart';
import 'package:shiksha_desk/modules/attendance/data/attendance_repository.dart';
import 'package:shiksha_desk/modules/messages/data/message_repository.dart';
import 'package:shiksha_desk/modules/results/data/result_repository.dart';
import 'package:shiksha_desk/modules/results/domain/result_models.dart';
import 'package:shiksha_desk/modules/students/application/student_profile_providers.dart';
import 'package:shiksha_desk/modules/students/application/student_profile_report.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/record_completeness.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/platform/academic/academic_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

StudentDetail _detail({
  bool withFather = false,
  String? photo,
  Map<String, String> extra = const {},
  List<String> years = const ['y1'],
}) =>
    StudentDetail(
      id: 's1',
      displayCode: 'STU-000001',
      status: StudentStatus.active,
      draft: StudentDraft(
        firstName: 'Fatima',
        lastName: 'Shaikh',
        gender: 'Female',
        dateOfBirth: DateTime(2009, 3, 24),
        photoFileName: photo,
        extra: {...extra},
      ),
      guardians: [
        const GuardianInfo(id: 'g1', name: 'Seema Farheen', relation: 'Mother', isPrimary: true, mobile: '9595459598'),
        if (withFather) const GuardianInfo(id: 'g2', name: 'Shakeel Ahmed', relation: 'Father', isPrimary: false),
      ],
      identifiers: const [
        IdentifierInfo(type: IdentifierType.grNumber, display: '1399'),
        IdentifierInfo(type: IdentifierType.aadhaar, display: 'XXXX XXXX 7881'),
      ],
      enrollments: [
        for (final y in years)
          EnrollmentInfo(
            id: 'e-$y',
            academicYearId: y,
            divisionId: 'd-$y',
            startDate: DateTime(2026, 6, 1),
            status: EnrollmentStatus.active,
          ),
      ],
    );

ExtraFieldDefinition _field(String key, {required bool required}) =>
    ExtraFieldDefinition(id: key, key: key, label: key, type: 'text', options: const [], isRequired: required);

void main() {
  group('record completeness', () {
    test('by default only the important items count; optional ones are not "missing"', () {
      final c = RecordCompleteness.evaluate(
        _detail(),
        checks: defaultCompletenessChecks,
        extraFields: const [],
        academicYearId: 'y1',
      );
      // Name, DOB, gender, parent mobile, class, G.R. and mother's name.
      expect(c.total, 7);
      expect(c.percent, 100);
      // Father's name and photo are not recorded but are not counted.
      expect(c.missing, isEmpty);
    });

    test('checks the institution switches on are counted', () {
      final c = RecordCompleteness.evaluate(
        _detail(),
        checks: {...defaultCompletenessChecks, CompletenessCheck.fatherName, CompletenessCheck.photo},
        extraFields: const [],
        academicYearId: 'y1',
      );
      expect(c.done, 7);
      expect(c.total, 9);
      expect(c.percent, 78);
      expect(c.missing.map((i) => i.check), [CompletenessCheck.fatherName, CompletenessCheck.photo]);

      final filled = RecordCompleteness.evaluate(
        _detail(withFather: true, photo: 'students/a.jpg'),
        checks: {...defaultCompletenessChecks, CompletenessCheck.fatherName, CompletenessCheck.photo},
        extraFields: const [],
        academicYearId: 'y1',
      );
      expect(filled.percent, 100);
    });

    test('own fields count only when marked required', () {
      final fields = [_field('fyjc_id', required: true), _field('hobby', required: false)];
      final missing = RecordCompleteness.evaluate(_detail(), checks: const {}, extraFields: fields, academicYearId: 'y1');
      expect(missing.total, 1);
      expect(missing.missing.single.extraField!.key, 'fyjc_id');
      final done = RecordCompleteness.evaluate(
        _detail(extra: {'fyjc_id': 'K0084131678'}),
        checks: const {},
        extraFields: fields,
        academicYearId: 'y1',
      );
      expect(done.percent, 100);
    });

    test('"class this year" follows the year shown', () {
      final other = RecordCompleteness.evaluate(
        _detail(),
        checks: {CompletenessCheck.classThisYear},
        extraFields: const [],
        academicYearId: 'y2',
      );
      expect(other.percent, 0);
    });

    test('the chosen checks are saved and read back', () {
      expect(RecordCompleteness.decodeChecks(null), defaultCompletenessChecks);
      expect(RecordCompleteness.decodeChecks('not json'), defaultCompletenessChecks);
      expect(RecordCompleteness.decodeChecks('[]'), isEmpty);
      final chosen = {CompletenessCheck.pen, CompletenessCheck.apaar};
      expect(RecordCompleteness.decodeChecks(RecordCompleteness.encodeChecks(chosen)), chosen);
      expect(RecordCompleteness.decodeChecks('["pen","no_such_check"]'), {CompletenessCheck.pen});
    });
  });

  group('academic year shown on the profile', () {
    AcademicYear year(String id, int start, AcademicYearStatus status) => AcademicYear(
          id: id,
          label: '$start-${(start + 1) % 100}',
          startDate: DateTime(start, 6, 1),
          endDate: DateTime(start + 1, 4, 30),
          status: status,
        );
    final academic = AcademicSnapshot(
      years: [
        year('y0', 2024, AcademicYearStatus.closed),
        year('y1', 2025, AcademicYearStatus.closed),
        year('y2', 2026, AcademicYearStatus.active),
      ],
      programs: const [],
      divisions: const [],
    );

    test('only real years: the ones enrolled in and the active year, newest first', () {
      expect(profileYears(academic, _detail(years: ['y1'])).map((y) => y.id), ['y2', 'y1']);
    });

    test('opens on the active year when enrolled in it, else the latest enrolled year', () {
      expect(defaultProfileYear(academic, _detail(years: ['y1', 'y2'])), 'y2');
      expect(defaultProfileYear(academic, _detail(years: ['y0', 'y1'])), 'y1');
      expect(enrollmentIn(_detail(years: ['y1']), 'y2'), isNull);
    });
  });

  group('with a database', () {
    late AppDatabase db;
    late StudentRepository students;
    late String yearId;
    late String divisionId;
    late String programId;
    late List<String> ids;
    final aadhaar = '23456789012${Aadhaar.checkDigit('23456789012')}';
    final today = DateTime(2026, 10, 14, 11);

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
      divisionId = academic.divisions.first.id;
      programId = academic.divisions.first.programId;
      students = StudentRepository(db, testSession, testCipher);
      ids = [
        for (final (i, name) in ['Ayaan', 'Rehan'].indexed)
          await students.create(StudentDraft(
            firstName: name,
            lastName: 'Shaikh',
            divisionId: divisionId,
            rollNumber: i + 1,
            admissionDate: DateTime(2026, 6, 15),
            guardians: [GuardianDraft(name: 'Parent $name', relation: 'Father', mobile: '98765432${10 + i}', isPrimary: true)],
            identifiers: {
              IdentifierType.grNumber: '${1246 + i}',
              if (i == 0) IdentifierType.aadhaar: aadhaar,
            },
          )),
      ];
    });
    tearDown(() => db.close());

    test('the printed profile never contains the full Aadhaar number', () async {
      final detail = (await students.load(ids[0]))!;
      final data = studentProfileDataset(
        AppLocalizationsEn(),
        detail: detail,
        extraFields: const [],
        divisionLabels: const {},
        yearLabels: {yearId: '2026-27'},
        yearLabel: '2026-27',
      );
      final text = [for (final r in data.rows) ...r.cells, ...data.subtitle, data.title].join(' ');
      expect(text.contains(aadhaar), isFalse);
      expect(text.replaceAll(' ', '').contains(aadhaar), isFalse);
      expect(text, contains(Aadhaar.mask(aadhaar.substring(8))));
      expect(text, contains('Ayaan Shaikh'));
      expect(text, contains('1246'));
    });

    test('attendance for a period: summary and latest days, newest first', () async {
      final attendance = AttendanceRepository(db, testSession, AppSettingsRepository(db, testSession), clock: () => today);
      await attendance.save(divisionId, DateTime(2026, 10, 13), {ids[0]: 'P', ids[1]: 'P'});
      await attendance.save(divisionId, DateTime(2026, 10, 14), {ids[0]: 'A', ids[1]: 'P'});

      final year = await attendance.studentPeriod(ids[0], from: DateTime(2026, 6, 1), to: DateTime(2026, 10, 14));
      expect(year.summary.present, 1);
      expect(year.summary.absent, 1);
      expect(year.recent.map((r) => r.$2), ['A', 'P']);

      final oneDay = await attendance.studentPeriod(ids[0], from: DateTime(2026, 10, 14), to: DateTime(2026, 10, 14));
      expect(oneDay.summary.days, 1);
    });

    test("a student's messages: only theirs, and only for the period", () async {
      final settings = AppSettingsRepository(db, testSession);
      final attendance = AttendanceRepository(db, testSession, settings, clock: () => today);
      final messages = MessageRepository(db, testSession, settings, attendance, students);
      await messages.recordFeeReminder(
        students: [(ids[0], 'Ayaan Shaikh', '11th Science A')],
        mobile: '9876543210',
        body: 'Fees pending',
        date: DateTime(2026, 10, 10),
      );
      await messages.recordFeeReminder(
        students: [(ids[1], 'Rehan Shaikh', '11th Science A')],
        mobile: '9876543211',
        body: 'Fees pending',
        date: DateTime(2026, 10, 10),
      );
      final mine = await messages.historyOfStudent(ids[0]);
      expect(mine, hasLength(1));
      expect(mine.single.studentNames, ['Ayaan Shaikh']);
      expect(mine.single.status, 'opened');
      expect(await messages.historyOfStudent(ids[0], from: DateTime(2026, 10, 11)), isEmpty);
    });

    test('results on the profile match the class sheet, and viewing creates no exams', () async {
      final results = ResultRepository(db, testSession, AppSettingsRepository(db, testSession), students);
      expect(await results.studentResults(ids[0], yearId), isNull);
      expect(await db.select(db.exams).get(), isEmpty);

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

      final mine = (await results.studentResults(ids[0], yearId))!;
      // 1st Term has no marks, so only the 2nd Term and the final result.
      expect(mine.lines.map((l) => l.exam?.name), ['2nd Term Examination', null]);
      final finalLine = mine.lines.last.result;
      expect(finalLine.total, 396);
      expect(finalLine.status, ResultStatus.passed);

      final sheet = await results.classResult(divisionId: divisionId, programId: programId, academicYearId: yearId);
      expect(finalLine.rank, sheet.results.firstWhere((r) => r.studentId == ids[0]).rank);
      expect(finalLine.rank, 2);
    });
  });
}
