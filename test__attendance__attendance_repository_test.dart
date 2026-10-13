import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/modules/attendance/data/attendance_repository.dart';
import 'package:shiksha_desk/modules/attendance/domain/attendance_models.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/platform/academic/academic_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

Matcher refused(AttendanceIssue issue) =>
    throwsA(isA<AttendanceException>().having((e) => e.issue, 'issue', issue));

void main() {
  // A fixed "today": Wednesday 14 October 2026.
  final today = DateTime(2026, 10, 14, 11);
  late AppDatabase db;
  late AttendanceRepository repo;
  late StudentRepository students;
  late AcademicSnapshot academic;
  late String divisionA;
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
    academic = await AcademicRepository(db, testSession).loadSnapshot();
    divisionA = academic.divisions.first.id;
    students = StudentRepository(db, testSession, testCipher);
    ids = [
      for (var i = 1; i <= 4; i++)
        await students.create(StudentDraft(
          firstName: 'Student$i',
          divisionId: divisionA,
          rollNumber: i,
          admissionDate: DateTime(2026, 6, 15),
        )),
    ];
    repo = AttendanceRepository(db, testSession, AppSettingsRepository(db, testSession), clock: () => today);
  });
  tearDown(() => db.close());

  Map<String, String> allPresent() => {for (final id in ids) id: 'P'};

  test('default marks P, A and L exist', () async {
    expect((await repo.codes()).map((c) => c.code), ['P', 'A', 'L']);
  });

  test('the sheet lists the division in roll order; saving and editing are recorded', () async {
    final sheet = await repo.sheet(divisionA, today);
    expect(sheet.roster.map((r) => r.rollNumber), [1, 2, 3, 4]);
    expect(sheet.isSaved, isFalse);

    await repo.save(divisionA, today, allPresent()..[ids[1]] = 'A');
    var saved = await repo.sheet(divisionA, today);
    expect(saved.marks[ids[1]], 'A');
    expect(saved.marks[ids[0]], 'P');

    await repo.save(divisionA, today, allPresent()..[ids[1]] = 'L');
    saved = await repo.sheet(divisionA, today);
    expect(saved.marks[ids[1]], 'L');
    expect(await db.select(db.attendanceSessions).get(), hasLength(1));

    final audit = await (db.select(db.auditEntries)..where((t) => t.entity.equals('attendance_sessions'))).get();
    expect(audit, hasLength(2));
    expect(audit.last.changes, contains('"old":"A"'));
  });

  test('future dates, Sundays, holidays and dates outside the edit window are refused', () async {
    await expectLater(repo.save(divisionA, today.add(const Duration(days: 1)), allPresent()), refused(AttendanceIssue.futureDate));
    await expectLater(repo.save(divisionA, DateTime(2026, 10, 11), allPresent()), refused(AttendanceIssue.notWorkingDay));
    await repo.setCalendarDay(DateTime(2026, 10, 13), DayKind.holiday, 'Test holiday');
    await expectLater(repo.save(divisionA, DateTime(2026, 10, 13), allPresent()), refused(AttendanceIssue.notWorkingDay));
    // "Mark anyway" on a holiday is allowed.
    await repo.save(divisionA, DateTime(2026, 10, 13), allPresent(), allowNonWorkingDay: true);
    // 8 days ago with a 7-day window.
    await expectLater(repo.save(divisionA, DateTime(2026, 10, 6), allPresent()), refused(AttendanceIssue.locked));
    await repo.setEditDays(30);
    await repo.save(divisionA, DateTime(2026, 10, 6), allPresent());
  });

  test('students appear only on dates they belonged to the division', () async {
    final late = await students.create(StudentDraft(
      firstName: 'Joined',
      divisionId: divisionA,
      rollNumber: 9,
      admissionDate: DateTime(2026, 10, 12),
    ));
    expect((await repo.roster(divisionA, DateTime(2026, 10, 9))).map((r) => r.studentId), isNot(contains(late)));
    expect((await repo.roster(divisionA, DateTime(2026, 10, 12))).map((r) => r.studentId), contains(late));

    await students.markLeft(ids[0], date: DateTime(2026, 10, 13), reason: 'Moved');
    expect((await repo.roster(divisionA, DateTime(2026, 10, 12))).map((r) => r.studentId), contains(ids[0]));
    expect((await repo.roster(divisionA, DateTime(2026, 10, 13))).map((r) => r.studentId), isNot(contains(ids[0])));
  });

  test('percentages: half days count half, excluded marks are not counted', () async {
    await repo.addCode(code: 'H', label: 'Half day', colorValue: 0xFF1565C0, countsAs: CountsAs.half);
    await repo.addCode(code: 'X', label: 'Exempt', colorValue: 0xFF455A64, countsAs: CountsAs.excluded);
    await repo.setEditDays(30);
    final days = [DateTime(2026, 10, 5), DateTime(2026, 10, 6), DateTime(2026, 10, 7), DateTime(2026, 10, 8), DateTime(2026, 10, 9)];
    final marksFor = ['P', 'A', 'H', 'X', 'P'];
    for (var i = 0; i < days.length; i++) {
      await repo.save(divisionA, days[i], allPresent()..[ids[0]] = marksFor[i]);
    }
    final s = await repo.studentSummary(ids[0], from: DateTime(2026, 10, 1), to: today);
    expect(s.present, 2.5);
    expect(s.absent, 1.5);
    expect(s.excluded, 1);
    expect(s.percent, closeTo(62.5, 0.001));
    expect(await repo.recentAbsences(ids[0]), [DateTime.utc(2026, 10, 6)]);

    final grid = await repo.monthGrid(divisionA, 2026, 10);
    expect(grid.marks[ids[0]]?[7], 'H');
    expect(grid.totals[ids[1]]?.percent, 100);
    expect(grid.dayKinds[11], DayKind.weeklyOff);

    final totals = await repo.dayTotals(DateTime(2026, 10, 6));
    expect(totals.present, 3);
    expect(totals.absent, 1);
  });

  test('a mark already used cannot be deleted; an unused one can', () async {
    await repo.save(divisionA, today, allPresent());
    final p = (await repo.codes()).firstWhere((c) => c.code == 'P');
    await expectLater(repo.deleteCode(p.id), refused(AttendanceIssue.codeInUse));
    final l = (await repo.codes()).firstWhere((c) => c.code == 'L');
    await repo.deleteCode(l.id);
    expect((await repo.codes()).map((c) => c.code), ['P', 'A']);
    await expectLater(
      repo.addCode(code: 'a', label: 'dup', colorValue: 0, countsAs: CountsAs.absent),
      refused(AttendanceIssue.duplicateCode),
    );
  });

  test('another institution sees none of this attendance', () async {
    await repo.save(divisionA, today, allPresent());
    final rows = await (db.select(db.attendanceRecords)..where((t) => t.organizationId.equals('other-org'))).get();
    expect(rows, isEmpty);
  });
}
