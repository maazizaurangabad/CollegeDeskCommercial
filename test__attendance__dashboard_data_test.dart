import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/modules/attendance/data/attendance_repository.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/platform/academic/academic_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/activity_repository.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

void main() {
  final today = DateTime(2026, 10, 14, 11); // a Wednesday
  late AppDatabase db;
  late AttendanceRepository attendance;
  late StudentRepository students;
  late AcademicSnapshot academic;
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
    students = StudentRepository(db, testSession, testCipher);
    final a = academic.divisions[0].id;
    final b = academic.divisions[1].id;
    ids = [
      await students.create(StudentDraft(firstName: 'Ayaan', divisionId: a, rollNumber: 1, admissionDate: DateTime(2026, 6, 15), dateOfBirth: DateTime(2010, 10, 14))),
      await students.create(StudentDraft(firstName: 'Riya', divisionId: a, rollNumber: 2, admissionDate: DateTime(2026, 6, 15))),
      await students.create(StudentDraft(firstName: 'Zoya', divisionId: b, rollNumber: 1, admissionDate: DateTime(2026, 6, 15))),
    ];
    attendance = AttendanceRepository(db, testSession, AppSettingsRepository(db, testSession), clock: () => today);
  });
  tearDown(() => db.close());

  test('divisions with students but no attendance today are listed', () async {
    final all = academic.divisions.map((d) => d.id);
    var unmarked = await attendance.unmarkedDivisions(today, all);
    expect(unmarked, [academic.divisions[0].id, academic.divisions[1].id]);
    await attendance.save(academic.divisions[0].id, today, {ids[0]: 'P', ids[1]: 'A'});
    unmarked = await attendance.unmarkedDivisions(today, all);
    expect(unmarked, [academic.divisions[1].id]);

    final absent = await attendance.absentOn(today);
    expect(absent.single.studentId, ids[1]);
    expect(absent.single.code, 'A');
  });

  test('low attendance lists students below 75% with enough marked days', () async {
    await attendance.setEditDays(30);
    final days = [5, 6, 7, 8, 9, 12, 13];
    for (var i = 0; i < days.length; i++) {
      // Riya is absent 4 of 7 days; Ayaan is always present.
      await attendance.save(academic.divisions[0].id, DateTime(2026, 10, days[i]), {ids[0]: 'P', ids[1]: i < 4 ? 'A' : 'P'});
    }
    final low = await attendance.lowAttendance(from: DateTime(2026, 10, 1), to: today);
    expect(low.map((l) => l.studentId), [ids[1]]);
    expect(low.single.summary.percent, closeTo(3 / 7 * 100, 0.01));
    // With fewer than 5 days counted, nobody is listed yet.
    expect(await attendance.lowAttendance(from: DateTime(2026, 10, 12), to: today), isEmpty);
  });

  test('birthdays today and recent activity', () async {
    final birthdays = await students.birthdaysOn(today);
    expect(birthdays.map((b) => b.id), [ids[0]]);

    await attendance.save(academic.divisions[0].id, today, {ids[0]: 'P', ids[1]: 'P'});
    final activity = await ActivityRepository(db, testSession).recent();
    expect(activity.first.entity, 'attendance_sessions');
    expect(activity.where((a) => a.entity == 'students' && a.action == 'insert'), hasLength(3));
    expect(activity.first.value('division_id'), academic.divisions[0].id);
  });
}
