import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/l10n/gen/app_localizations_en.dart';
import 'package:shiksha_desk/modules/attendance/data/attendance_repository.dart';
import 'package:shiksha_desk/modules/messages/application/messages_providers.dart';
import 'package:shiksha_desk/modules/messages/data/message_repository.dart';
import 'package:shiksha_desk/modules/messages/domain/message_models.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

void main() {
  test('WhatsApp links carry the India code and the typed message', () {
    expect(WhatsAppLink.chat('098765 43210', 'Hi there').toString(), 'https://wa.me/919876543210?text=Hi%20there');
    expect(WhatsAppLink.pickChat('A&B').toString(), 'https://wa.me/?text=A%26B');
  });

  test('templates fill every word and leave unknown words alone', () {
    final text = MessagePlaceholders.fill('{student} ({class}) {days} {other}', {
      MessagePlaceholders.student: 'Ayaan',
      MessagePlaceholders.className: '11th Science A',
      MessagePlaceholders.days: '3',
    });
    expect(text, 'Ayaan (11th Science A) 3 {other}');
  });

  group('messages to parents', () {
    // Wednesday 14 October 2026; Monday 12 and Tuesday 13 are working days.
    final today = DateTime(2026, 10, 14, 11);
    final monday = DateTime(2026, 10, 12);
    final tuesday = DateTime(2026, 10, 13);
    late AppDatabase db;
    late AttendanceRepository attendance;
    late MessageRepository messages;
    late String division;
    late Map<String, String> labels;
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
      final academicRepo = AcademicRepository(db, testSession);
      final academic = await academicRepo.loadSnapshot();
      division = academic.divisions.first.id;
      labels = await academicRepo.divisionLabels();
      final students = StudentRepository(db, testSession, testCipher);
      Future<String> add(String name, int roll, List<GuardianDraft> guardians) => students.create(StudentDraft(
            firstName: name,
            lastName: 'Shaikh',
            divisionId: division,
            rollNumber: roll,
            admissionDate: DateTime(2026, 6, 15),
            guardians: guardians,
          ));
      ids = [
        // Two siblings: the same number, written differently, on two guardian records.
        await add('Ayaan', 1, [GuardianDraft(name: 'Shabana Shaikh', relation: 'Mother', mobile: '98765 43210', isPrimary: true)]),
        await add('Sara', 2, [GuardianDraft(name: 'Salim Shaikh', relation: 'Father', mobile: '+91 9876543210', isPrimary: true)]),
        // No number on record.
        await add('Zaid', 3, []),
        // On leave.
        await add('Imran', 4, [GuardianDraft(name: 'Rafiq Shaikh', relation: 'Father', mobile: '9123456789', isPrimary: true)]),
        // Present.
        await add('Huda', 5, [GuardianDraft(name: 'Nasreen Shaikh', relation: 'Mother', mobile: '9988776655', isPrimary: true)]),
      ];
      final settings = AppSettingsRepository(db, testSession);
      attendance = AttendanceRepository(db, testSession, settings, clock: () => today);
      messages = MessageRepository(db, testSession, settings, attendance, students);

      Map<String, String> marks(String ayaan) =>
          {ids[0]: ayaan, ids[1]: 'P', ids[2]: 'P', ids[3]: 'P', ids[4]: 'P'};
      await attendance.save(division, monday, marks('A'));
      await attendance.save(division, tuesday, marks('A'));
      await attendance.save(division, today, {ids[0]: 'A', ids[1]: 'A', ids[2]: 'A', ids[3]: 'L', ids[4]: 'P'});
    });
    tearDown(() => db.close());

    Future<List<AbsentFamily>> families() =>
        messages.absentFamilies(today, institution: 'Test College', divisionLabels: labels);

    test('days absent in a row are counted', () async {
      final streaks = await attendance.absentStreaks(ids, today);
      expect(streaks[ids[0]], 3);
      expect(streaks[ids[1]], 1);
      expect(streaks[ids[4]], 0);
    });

    test('siblings get one message; no number is listed apart; leave is not messaged by default', () async {
      final list = await families();
      expect(list, hasLength(2));
      final family = list.firstWhere((f) => f.hasNumber);
      expect(family.mobile, '9876543210');
      expect(family.students.map((s) => s.fullName), ['Ayaan Shaikh', 'Sara Shaikh']);
      expect(family.kind, MessageKind.absent);
      expect(family.body, contains('Ayaan Shaikh and Sara Shaikh'));
      expect(family.body, contains('14 Oct 2026'));
      expect(family.body, contains('Test College'));
      expect(family.isSent, isFalse);

      final none = list.firstWhere((f) => !f.hasNumber);
      expect(none.students.single.studentId, ids[2]);
    });

    test('leave can be switched on, and the streak text is used from the chosen number of days', () async {
      final s = await messages.loadSettings();
      expect(s.codes, {'A'});
      await messages.saveSettings(MessageSettings(
        absentTemplate: 'Absent: {student}',
        streakTemplate: 'Streak: {student} {days}',
        streakDays: 3,
        codes: {'A', 'L'},
      ));
      final list = await families();
      expect(list, hasLength(3));
      final leave = list.firstWhere((f) => f.mobile == '9123456789');
      expect(leave.body, 'Absent: Imran Shaikh');

      // Ayaan alone (3 days) would get the streak text.
      final ayaan = list.firstWhere((f) => f.mobile == '9876543210').students.first;
      expect(MessageRepository.fillBody('Streak: {student} {days}', [ayaan], date: today, days: ayaan.streak, institution: ''),
          'Streak: Ayaan Shaikh 3');
    });

    test('a sent message is ticked, kept in history and audited', () async {
      final family = (await families()).firstWhere((f) => f.hasNumber);
      await messages.recordSent(family, today, body: 'Edited text');

      final again = (await families()).firstWhere((f) => f.hasNumber);
      expect(again.isSent, isTrue);
      expect(await messages.countForDate(today), 1);

      final history = await messages.history();
      expect(history, hasLength(1));
      expect(history.single.studentNames, ['Ayaan Shaikh', 'Sara Shaikh']);
      expect(history.single.body, 'Edited text');
      expect(history.single.mobile, '9876543210');
      expect(await messages.history(query: 'sara'), hasLength(1));
      expect(await messages.history(query: 'nobody'), isEmpty);
      expect(await messages.history(from: DateTime(2026, 10, 15)), isEmpty);

      final audit = await (db.select(db.auditEntries)..where((t) => t.entity.equals('message_logs'))).get();
      expect(audit, hasLength(2));
    });

    test('the day summary lists classes, counts and absent names', () async {
      final summary = await messages.daySummary(today, divisions: [(division, 'Class A')]);
      expect(summary.present, 1);
      expect(summary.absent, 4);
      final text = daySummaryText(AppLocalizationsEn(), summary, institution: 'Test College');
      expect(text, contains('Class A: Present 1, Absent 4'));
      expect(text, contains('1. Ayaan Shaikh'));
      expect(text, contains('4. Imran Shaikh (L)'));
      expect(text, contains('Total: Present 1, Absent 4 (20.0%)'));

      await messages.recordSummary(today, text);
      final history = await messages.history();
      expect(history.single.kind, MessageKind.summary);
      expect(await messages.countForDate(today), 0);
    });

    test('history exports as a report with one row per message', () async {
      final family = (await families()).firstWhere((f) => f.hasNumber);
      await messages.recordSent(family, today);
      final data = messageHistoryDataset(AppLocalizationsEn(), await messages.history());
      expect(data.dataRowCount, 1);
      expect(data.rows.single.cells[4], 'Ayaan Shaikh, Sara Shaikh');
    });
  });
}
