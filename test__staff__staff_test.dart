import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/security/pin_hasher.dart';
import 'package:shiksha_desk/core/session/app_session.dart';
import 'package:shiksha_desk/modules/students/documents/document_models.dart';
import 'package:shiksha_desk/modules/students/documents/document_repository.dart';
import 'package:shiksha_desk/platform/data/activity_repository.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/staff/route_permissions.dart';
import 'package:shiksha_desk/platform/staff/staff_models.dart';
import 'package:shiksha_desk/platform/staff/staff_providers.dart';
import 'package:shiksha_desk/platform/staff/staff_repository.dart';

import '../test_support.dart';

void main() {
  group('who may do what', () {
    test('the administrator may do everything; staff only what their role allows', () {
      expect(CurrentUser.owner.can(Permissions.backupManage), isTrue);
      expect(CurrentUser.owner.can(Permissions.ownerOnly), isTrue);
      final teacher = StaffRoles.defaults.firstWhere((r) => r.key == StaffRoles.teacherKey);
      final user = CurrentUser(id: 's1', name: 'Asma', roleKey: teacher.key, permissions: teacher.permissions);
      expect(user.can(Permissions.attendanceMark), isTrue);
      expect(user.can(Permissions.feesCollect), isFalse);
      // Even a staff Admin cannot open other institutions or the app lock.
      final admin = StaffRoles.defaults.first;
      final staffAdmin = CurrentUser(id: 's2', name: 'X', roleKey: admin.key, permissions: admin.permissions);
      expect(staffAdmin.can(Permissions.staffManage), isTrue);
      expect(staffAdmin.can(Permissions.ownerOnly), isFalse);
    });

    test('pages that need more than seeing their section', () {
      expect(permissionForPath('/students'), isNull);
      expect(permissionForPath('/students/abc'), isNull);
      expect(permissionForPath('/students/new'), Permissions.studentsEdit);
      expect(permissionForPath('/students/abc/edit'), Permissions.studentsEdit);
      expect(permissionForPath('/students/import'), Permissions.studentsImport);
      expect(permissionForPath('/students/promotion'), Permissions.studentsPromote);
      expect(permissionForPath('/fees/setup'), Permissions.feesSetup);
      expect(permissionForPath('/fees/pay'), isNull);
      expect(permissionForPath('/settings'), isNull);
      expect(permissionForPath('/settings/staff/roles'), Permissions.staffManage);
      expect(permissionForPath('/settings/backup'), Permissions.backupManage);
      expect(permissionForPath('/settings/security'), Permissions.ownerOnly);
      expect(permissionForPath('/settings/classes'), Permissions.settingsManage);
      expect(permissionForPath('/settings/activity'), Permissions.staffManage);
    });

    test('changes are recorded under whoever is logged in at that moment', () {
      String? who;
      final session = AppSession(organizationId: 'o', deviceId: 'd', userId: 'local-admin', activeUserId: () => who);
      expect(session.userId, 'local-admin');
      who = 'staff-1';
      expect(session.userId, 'staff-1');
    });
  });

  test('staff: add with a PIN, log in, switch off', () async {
    final db = newMemoryDatabase();
    addTearDown(db.close);
    final repo = StaffRepository(db, testSession, hasher: PinHasher(iterations: 1000));
    expect(await repo.logins(), isEmpty);

    await expectLater(repo.save(const StaffMember(name: 'Asma', roleKey: 'teacher')), throwsA(isA<StaffException>()));
    final id = await repo.save(const StaffMember(name: ' Asma Shaikh ', roleKey: 'teacher', mobile: '9876543210'), pin: '2468');

    final logins = await repo.logins();
    expect(logins.single.name, 'Asma Shaikh');
    expect(logins.single.roleLabel, 'Teacher');
    expect(await repo.verifyPin(id, '2468'), isTrue);
    expect(await repo.verifyPin(id, '1111'), isFalse);
    final access = (await repo.accessFor(id))!;
    expect(access.can(Permissions.attendanceMark), isTrue);
    expect(access.can(Permissions.feesCollect), isFalse);

    // Editing without a PIN keeps the old one.
    final member = (await repo.list()).single;
    await repo.save(member.copyWith(roleKey: 'accountant'));
    expect(await repo.verifyPin(id, '2468'), isTrue);
    expect((await repo.accessFor(id))!.can(Permissions.feesCollect), isTrue);

    // Switched off: cannot log in any more.
    await repo.save((await repo.list()).single.copyWith(active: false));
    expect(await repo.logins(), isEmpty);
    expect(await repo.verifyPin(id, '2468'), isFalse);
    expect(await repo.accessFor(id), isNull);
  });

  test('roles: custom roles are saved; the standard ones always stay', () async {
    final db = newMemoryDatabase();
    addTearDown(db.close);
    final repo = StaffRepository(db, testSession, hasher: PinHasher(iterations: 1000));
    final roles = await repo.roles();
    await repo.saveRoles([
      ...roles,
      const StaffRole(key: 'librarian', label: 'Librarian', permissions: {Permissions.studentsView}),
    ]);
    final back = await repo.roles();
    expect(back.map((r) => r.key), containsAll(['admin', 'principal', 'clerk', 'accountant', 'teacher', 'librarian']));
    expect(back.last.permissions, {Permissions.studentsView});
  });

  test('activity log: who did what, by person and day', () async {
    final db = newMemoryDatabase();
    addTearDown(db.close);
    String? who;
    final session = AppSession(
      organizationId: testSession.organizationId,
      deviceId: 'd',
      userId: localAdminUserId,
      activeUserId: () => who,
    );
    final docs = DocumentRepository(db, session, AppSettingsRepository(db, session));
    await docs.save(const StudentDocument(studentId: 's1', typeKey: 'photos'));
    who = 'staff-1';
    await docs.save(const StudentDocument(studentId: 's2', typeKey: 'photos'));

    final log = ActivityRepository(db, session);
    final today = DateTime.now();
    final all = await log.log(from: today, to: today);
    expect(all, hasLength(2));
    expect(all.map((e) => e.userId).toSet(), {'staff-1', localAdminUserId});
    expect((await log.log(userId: 'staff-1', from: today, to: today)).single.entity, 'student_documents');
    final yesterday = today.subtract(const Duration(days: 1));
    expect(await log.log(from: yesterday, to: yesterday), isEmpty);

    expect(userDisplayName({'staff-1': 'Asma'}, 'staff-1'), 'Asma');
    expect(userDisplayName(const {}, localAdminUserId), 'Admin');
    expect(userDisplayName(const {}, null), isNull);
  });
}
