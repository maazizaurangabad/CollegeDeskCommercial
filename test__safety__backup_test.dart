import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shiksha_desk/core/backup/auto_backup.dart';
import 'package:shiksha_desk/core/backup/backup_codec.dart';
import 'package:shiksha_desk/core/backup/backup_service.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/core/database/data_health.dart';
import 'package:shiksha_desk/core/validation/aadhaar.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';

import '../test_support.dart';

void main() {
  final aadhaar = '23456789012${Aadhaar.checkDigit('23456789012')}';

  test('the codec opens with the right password and refuses a wrong one or a damaged file', () async {
    final plain = Uint8List.fromList(List<int>.generate(5000, (i) => i % 251));
    final sealed = await BackupCodec.seal(plain, 'correct horse');
    expect(BackupCodec.isBackup(sealed), isTrue);
    expect(await BackupCodec.open(sealed, 'correct horse'), plain);
    await expectLater(BackupCodec.open(sealed, 'wrong password'), throwsA(isA<BackupPasswordException>()));
    final damaged = Uint8List.fromList(sealed)..[sealed.length ~/ 2] ^= 0xFF;
    await expectLater(BackupCodec.open(damaged, 'correct horse'), throwsA(isA<BackupPasswordException>()));
    await expectLater(BackupCodec.open(Uint8List.fromList(List.filled(100, 1)), 'x'), throwsA(isA<BackupFormatException>()));
  });

  test('a full institution backs up and restores into an empty database, photos included', () async {
    final startup = await newTestStartup(demoStudentCount: 25);
    final source = startup.database;
    final students = StudentRepository(source, testSession, testCipher);
    final id = await students.create(StudentDraft(
      firstName: 'Backup',
      lastName: 'Test',
      identifiers: {IdentifierType.aadhaar: aadhaar, IdentifierType.grNumber: 'B-1'},
    ));

    final media = await Directory.systemTemp.createTemp('sd_media_');
    await File(p.join(media.path, 'students', 'x.jpg')).create(recursive: true);
    await File(p.join(media.path, 'students', 'x.jpg')).writeAsBytes([1, 2, 3]);

    final bytes = await BackupService.create(
      db: source,
      organizationId: testSession.organizationId,
      organizationName: 'Test College',
      isDemo: false,
      mediaDir: media,
      password: 'backup-pass-1',
      fieldKeyHex: 'ab' * 64,
    );
    final contents = await BackupService.open(bytes, 'backup-pass-1', currentSchemaVersion: AppDatabase.currentSchemaVersion);
    expect(contents.manifest.studentCount, 26);
    expect(contents.manifest.fieldKeyHex, 'ab' * 64);
    expect(contents.media['students/x.jpg'], [1, 2, 3]);

    final target = newMemoryDatabase();
    await BackupService.writeInto(target, contents);
    for (final table in source.allTables) {
      final a = await source.customSelect('SELECT count(*) AS c FROM "${table.actualTableName}"').getSingle();
      final b = await target.customSelect('SELECT count(*) AS c FROM "${table.actualTableName}"').getSingle();
      expect(b.read<int>('c'), a.read<int>('c'), reason: table.actualTableName);
    }
    final restored = StudentRepository(target, testSession, testCipher);
    final detail = await restored.load(id);
    expect(detail!.draft.firstName, 'Backup');
    expect(await restored.revealAadhaar(id), Aadhaar.format(aadhaar));

    await expectLater(
      BackupService.open(bytes, 'backup-pass-1', currentSchemaVersion: 1),
      throwsA(isA<BackupTooNewException>()),
    );
    await source.close();
    await target.close();
    await media.delete(recursive: true);
  });

  test('automatic backups keep 7 daily and up to 4 weekly; old safety copies go after 30 days', () {
    final today = DateTime(2026, 10, 9);
    final names = [
      for (var i = 0; i < 40; i++) AutoBackupPolicy.dailyName(today.subtract(Duration(days: i))),
      'before-import-old.sdbak',
      'before-import-new.sdbak',
    ];
    final delete = AutoBackupPolicy.toDelete(names, today, modified: {
      'before-import-old.sdbak': today.subtract(const Duration(days: 45)),
      'before-import-new.sdbak': today.subtract(const Duration(days: 2)),
    });
    final kept = names.where((n) => !delete.contains(n)).toList();
    final keptDaily = kept.where((n) => n.startsWith('auto-')).toList();
    expect(keptDaily.take(7), [for (var i = 0; i < 7; i++) AutoBackupPolicy.dailyName(today.subtract(Duration(days: i)))]);
    expect(keptDaily.length, lessThanOrEqualTo(11));
    expect(delete, contains('before-import-old.sdbak'));
    expect(delete, isNot(contains('before-import-new.sdbak')));
  });

  test('data health finds a roll number used twice', () async {
    final startup = await newTestStartup(demoStudentCount: 4);
    final db = startup.database;
    final yearId = startup.academic.activeYear!.id;
    var findings = await DataHealth.run(db, testSession.organizationId, activeYearId: yearId);
    expect(findings.every((f) => f.ok), isTrue);

    // Force a clash behind the app's back, as damage would.
    final rows = await (db.select(db.enrollments)..limit(2)).get();
    await (db.update(db.enrollments)..where((t) => t.id.equals(rows[1].id)))
        .write(EnrollmentsCompanion(divisionId: Value(rows[0].divisionId), rollNumber: Value(rows[0].rollNumber)));
    findings = await DataHealth.run(db, testSession.organizationId, activeYearId: yearId);
    expect(findings.firstWhere((f) => f.check == HealthCheck.duplicateRolls).count, 1);
    await db.close();
  });
}
