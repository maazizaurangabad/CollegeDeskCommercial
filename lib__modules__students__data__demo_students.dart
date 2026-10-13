import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/ids/uuid7.dart';
import '../../../core/session/app_session.dart';
import '../domain/student_models.dart';

/// Fictional students for the demo institution, so lists and search can be
/// tried at a realistic size. Fixed seed: every device gets the same names.
/// Never real people.
abstract final class DemoStudents {
  static const _boys = [
    'Aarav', 'Ayaan', 'Kabir', 'Rohan', 'Arjun', 'Zaid', 'Imran', 'Vivek', 'Sahil', 'Faizan', 'Omkar', 'Yash',
    'Danish', 'Pranav', 'Rehan', 'Tanmay', 'Aditya', 'Harsh', 'Irfan', 'Siddharth',
  ];
  static const _girls = [
    'Ananya', 'Sana', 'Isha', 'Zoya', 'Pooja', 'Aisha', 'Neha', 'Mehak', 'Shruti', 'Fatima', 'Riya', 'Sneha',
    'Alina', 'Kavya', 'Nida', 'Tanvi', 'Sakshi', 'Hiba', 'Pallavi', 'Ruhi',
  ];
  static const _surnames = [
    'Patil', 'Shaikh', 'Deshmukh', 'Khan', 'Jadhav', 'Pathan', 'Kulkarni', 'Sayyed', 'Pawar', 'Qureshi',
    'More', 'Ansari', 'Gaikwad', 'Siddiqui', 'Shinde', 'Mirza', 'Kale', 'Bagwan', 'Joshi', 'Inamdar',
  ];
  static const _fathers = [
    'Rajesh', 'Salim', 'Sunil', 'Anwar', 'Prakash', 'Rafiq', 'Ganesh', 'Javed', 'Mahesh', 'Asif',
  ];

  /// Inserts [count] students spread over [divisionsByYear] in one batch.
  static Future<void> seed(
    AppDatabase db,
    AppSession session, {
    required String academicYearId,
    required List<String> divisionIds,
    int count = 500,
  }) async {
    if (divisionIds.isEmpty || count <= 0) return;
    final random = Random(20261009);
    final ts = DateTime.now().toUtc();
    final rolls = <String, int>{};
    final orgId = session.organizationId;

    await db.batch((batch) {
      for (var i = 0; i < count; i++) {
        final isGirl = random.nextBool();
        final first = (isGirl ? _girls : _boys)[random.nextInt(20)];
        final surname = _surnames[random.nextInt(_surnames.length)];
        final father = _fathers[random.nextInt(_fathers.length)];
        final code = 'STU-${(i + 1).toString().padLeft(6, '0')}';
        final gr = '${1000 + i}';
        final mobile = '9${(100000000 + random.nextInt(899999999))}';
        final divisionId = divisionIds[i % divisionIds.length];
        final roll = (rolls[divisionId] ?? 0) + 1;
        rolls[divisionId] = roll;
        final studentId = Uuid7.generate(ts);
        final guardianId = Uuid7.generate(ts);
        final dob = DateTime.utc(2009 + random.nextInt(2), 1 + random.nextInt(12), 1 + random.nextInt(28));

        batch.insert(
          db.students,
          StudentsCompanion.insert(
            id: studentId,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            deviceId: session.deviceId,
            displayCode: code,
            firstName: first,
            middleName: Value(father),
            lastName: Value(surname),
            gender: Value(isGirl ? 'Female' : 'Male'),
            dateOfBirth: Value(dob),
            nationality: const Value('Indian'),
            bloodGroup: Value(StudentChoices.bloodGroups[random.nextInt(8)]),
            searchText: Value('$first $father $surname $code $gr $father $surname $mobile'.toLowerCase()),
          ),
        );
        batch.insert(
          db.guardians,
          GuardiansCompanion.insert(
            id: guardianId,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            deviceId: session.deviceId,
            name: '$father $surname',
            relation: 'Father',
            mobile: Value(mobile),
          ),
        );
        batch.insert(
          db.studentGuardians,
          StudentGuardiansCompanion.insert(
            id: Uuid7.generate(ts),
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            deviceId: session.deviceId,
            studentId: studentId,
            guardianId: guardianId,
            isPrimary: const Value(true),
          ),
        );
        batch.insert(
          db.studentIdentifiers,
          StudentIdentifiersCompanion.insert(
            id: Uuid7.generate(ts),
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            deviceId: session.deviceId,
            studentId: studentId,
            idType: IdentifierType.grNumber.code,
            idValue: gr,
          ),
        );
        batch.insert(
          db.enrollments,
          EnrollmentsCompanion.insert(
            id: Uuid7.generate(ts),
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            deviceId: session.deviceId,
            studentId: studentId,
            academicYearId: academicYearId,
            divisionId: divisionId,
            rollNumber: Value(roll),
            startDate: DateTime.utc(2026, 6, 15),
            status: EnrollmentStatus.active.name,
          ),
        );
      }
      batch.insert(
        db.sequences,
        SequencesCompanion.insert(organizationId: orgId, name: 'student_code', nextValue: count + 1),
        mode: InsertMode.insertOrReplace,
      );
    });
  }
}
