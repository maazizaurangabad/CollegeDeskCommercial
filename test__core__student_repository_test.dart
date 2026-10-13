import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/core/session/app_session.dart';
import 'package:shiksha_desk/core/validation/aadhaar.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/platform/academic/academic_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

Matcher refused(StudentIssue issue) =>
    throwsA(isA<StudentValidationException>().having((e) => e.issue, 'issue', issue));

void main() {
  late AppDatabase db;
  late StudentRepository repo;
  late AcademicSnapshot academic;
  final aadhaar = '23456789012${Aadhaar.checkDigit('23456789012')}';

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
    repo = StudentRepository(db, testSession, testCipher);
  });
  tearDown(() => db.close());

  String divisionA() => academic.divisions.first.id;

  StudentDraft sample({String first = 'Ayaan', String last = 'Shaikh', String? gr, int? roll}) => StudentDraft(
        firstName: first,
        lastName: last,
        dateOfBirth: DateTime(2010, 3, 14),
        bloodGroup: 'B+',
        heightCm: 152.5,
        caste: 'Example caste',
        guardians: [GuardianDraft(name: 'Salim Shaikh', relation: 'Father', mobile: '98765 43210', isPrimary: true)],
        identifiers: {if (gr != null) IdentifierType.grNumber: gr},
        divisionId: divisionA(),
        rollNumber: roll,
      );

  test('a new student gets a code, is placed and can be found by name, code, GR and mobile', () async {
    final id = await repo.create(sample(gr: 'G-101', roll: 1));
    final detail = await repo.load(id);
    expect(detail!.displayCode, 'STU-000001');
    expect(detail.activeEnrollment?.divisionId, divisionA());
    expect(detail.draft.heightCm, 152.5);
    expect(detail.draft.caste, 'Example caste');
    expect(detail.guardians.single.mobile, '9876543210');

    for (final q in ['ayaan', 'STU-000001', 'g-101', '9876543210', 'ayaan shaikh']) {
      expect(await repo.list(query: q, academicYearId: academic.activeYear!.id), hasLength(1), reason: q);
    }
    expect(await repo.list(query: 'nobody'), isEmpty);
    final listed = await repo.list(academicYearId: academic.activeYear!.id);
    expect(listed.single.rollNumber, 1);
    expect(listed.single.primaryMobile, '9876543210');
  });

  test('codes are never reused, even after deletion', () async {
    final a = await repo.create(sample());
    await repo.moveToRecycleBin(a);
    final b = await repo.create(sample(first: 'Zoya'));
    expect((await repo.load(b))!.displayCode, 'STU-000002');
  });

  test('the same roll number in the same division is refused', () async {
    await repo.create(sample(roll: 5));
    await expectLater(() => repo.create(sample(first: 'Zoya', roll: 5)), refused(StudentIssue.duplicateRoll));
  });

  test('official numbers are unique, ignoring case', () async {
    await repo.create(sample(gr: 'G-7'));
    await expectLater(() => repo.create(sample(first: 'Zoya', gr: 'g-7')), refused(StudentIssue.duplicateIdentifier));
  });

  test('Aadhaar: invalid refused; valid stored encrypted, shown masked, revealing is logged', () async {
    final bad = sample()..identifiers[IdentifierType.aadhaar] = '234567890123';
    if (!Aadhaar.isValid('234567890123')) {
      await expectLater(() => repo.create(bad), refused(StudentIssue.invalidAadhaar));
    }

    final good = sample()..identifiers[IdentifierType.aadhaar] = aadhaar;
    final id = await repo.create(good);
    final row = await (db.select(db.studentIdentifiers)..where((t) => t.idType.equals('aadhaar'))).getSingle();
    expect(row.idValue.contains(aadhaar), isFalse);
    expect((await repo.load(id))!.identifier(IdentifierType.aadhaar), 'XXXX XXXX ${aadhaar.substring(8)}');

    final audits = await db.select(db.auditEntries).get();
    expect(audits.any((a) => a.changes.contains(aadhaar)), isFalse);

    expect(await repo.revealAadhaar(id), Aadhaar.format(aadhaar));
    final reveal = (await db.select(db.auditEntries).get()).where((a) => a.action == 'reveal');
    expect(reveal, hasLength(1));

    final twin = sample(first: 'Zoya')..identifiers[IdentifierType.aadhaar] = aadhaar;
    await expectLater(() => repo.create(twin), refused(StudentIssue.duplicateIdentifier));
  });

  test('editing without retyping Aadhaar keeps it; removing it deletes it', () async {
    final id = await repo.create(sample()..identifiers[IdentifierType.aadhaar] = aadhaar);
    final edit = (await repo.load(id))!.draft..lastName = 'Khan';
    await repo.update(id, edit);
    expect((await repo.load(id))!.identifier(IdentifierType.aadhaar), isNotNull);
    final remove = (await repo.load(id))!.draft..identifiers[IdentifierType.aadhaar] = '';
    await repo.update(id, remove);
    expect((await repo.load(id))!.identifier(IdentifierType.aadhaar), isNull);
  });

  test('possible duplicates are found before saving', () async {
    await repo.create(sample(gr: 'G-1'));
    final sameNameDob = await repo.findDuplicates(sample());
    expect(sameNameDob.map((m) => m.reason), contains(DuplicateReason.sameNameAndBirthDate));
    final sameMobile = await repo.findDuplicates(StudentDraft(
      firstName: 'Ayaan',
      guardians: [GuardianDraft(name: 'X', mobile: '9876543210')],
    ));
    expect(sameMobile.map((m) => m.reason), contains(DuplicateReason.sameMobileSimilarName));
    expect(await repo.findDuplicates(StudentDraft(firstName: 'Completely', lastName: 'Different')), isEmpty);
  });

  test('marking as left ends the enrollment and keeps history', () async {
    final id = await repo.create(sample(roll: 3));
    await repo.markLeft(id, date: DateTime(2026, 11, 1), reason: 'Transfer to another city');
    final detail = (await repo.load(id))!;
    expect(detail.status, StudentStatus.left);
    expect(detail.leavingReason, 'Transfer to another city');
    expect(detail.activeEnrollment, isNull);
    expect(detail.enrollments.single.status, EnrollmentStatus.left);
    expect(await repo.list(status: StudentStatus.active), isEmpty);
    // The roll number is free again.
    await repo.create(sample(first: 'Zoya', roll: 3));
  });

  test('moving division closes one enrollment and opens another', () async {
    final id = await repo.create(sample(roll: 1));
    final other = academic.divisions[1].id;
    final edit = (await repo.load(id))!.draft..divisionId = other;
    await repo.update(id, edit);
    final detail = (await repo.load(id))!;
    expect(detail.activeEnrollment?.divisionId, other);
    expect(detail.enrollments.map((e) => e.status), containsAll([EnrollmentStatus.active, EnrollmentStatus.transferred]));
  });

  test('recycle bin hides, then restores, the student', () async {
    final id = await repo.create(sample());
    await repo.moveToRecycleBin(id);
    expect(await repo.list(), isEmpty);
    expect((await repo.listRecycleBin()).single.id, id);
    await repo.restore(id);
    expect(await repo.list(), hasLength(1));
  });

  test('a division with students cannot be deleted', () async {
    await repo.create(sample());
    await expectLater(
      () => AcademicRepository(db, testSession).deleteDivision(divisionA()),
      throwsA(isA<AcademicValidationException>().having((e) => e.issue, 'issue', AcademicIssue.divisionHasStudents)),
    );
  });

  test('a required extra field must be filled', () async {
    const field = ExtraFieldDefinition(id: 'f', key: 'hostel', label: 'Hostel room', type: 'text', options: [], isRequired: true);
    await expectLater(() => repo.create(sample(), extraFields: [field]), refused(StudentIssue.requiredFieldMissing));
    final ok = sample()..extra['hostel'] = 'B-12';
    final id = await repo.create(ok, extraFields: [field]);
    expect((await repo.load(id))!.draft.extra['hostel'], 'B-12');
    final row = await (db.select(db.students)..where((t) => t.id.equals(id))).getSingle();
    expect(jsonDecode(row.extraJson), {'hostel': 'B-12'});
  });

  test('another institution sees none of these students', () async {
    await repo.create(sample());
    const otherSession = AppSession(organizationId: 'org-other', deviceId: 'd', userId: 'u');
    final other = StudentRepository(db, otherSession, testCipher);
    expect(await other.list(), isEmpty);
  });
}
