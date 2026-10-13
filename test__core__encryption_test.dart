import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/core/database/pre_migration_backup.dart';
import 'package:shiksha_desk/core/ids/uuid7.dart';
import 'package:shiksha_desk/core/session/app_session.dart';
import 'package:shiksha_desk/platform/data/organization_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tempDir;
  final key = Uuid7.randomHex(32);
  const session = AppSession(organizationId: 'org-enc', deviceId: 'dev', userId: 'user');

  setUp(() async => tempDir = await Directory.systemTemp.createTemp('sd_encryption_'));
  tearDown(() async => tempDir.delete(recursive: true));

  Future<File> createEncryptedDatabase() async {
    final file = File(p.join(tempDir.path, 'org.db'));
    final db = AppDatabase(AppDatabase.openEncrypted(file, key));
    await OrganizationRepository(db, session).create(DemoData.organization);
    await db.close();
    return file;
  }

  test('the bundled SQLite supports encryption', () {
    final raw = sqlite3.openInMemory();
    expect(raw.select('PRAGMA cipher;'), isNotEmpty);
    raw.close();
  });

  test('the database file cannot be read without its key', () async {
    final file = await createEncryptedDatabase();

    final header = file.readAsBytesSync().sublist(0, 15);
    expect(String.fromCharCodes(header), isNot('SQLite format 3'));

    final noKey = sqlite3.open(file.path);
    expect(() => noKey.select('SELECT count(*) FROM sqlite_master'), throwsA(isA<SqliteException>()));
    noKey.close();

    final wrongKey = sqlite3.open(file.path);
    wrongKey.execute("PRAGMA key = '${Uuid7.randomHex(32)}';");
    expect(() => wrongKey.select('SELECT count(*) FROM sqlite_master'), throwsA(isA<SqliteException>()));
    wrongKey.close();
  });

  test('the right key opens it and the data is intact', () async {
    final file = await createEncryptedDatabase();
    final db = AppDatabase(AppDatabase.openEncrypted(file, key));
    final org = await OrganizationRepository(db, session).loadActive();
    expect(org?.name, DemoData.organization.name);
    await db.close();
  });

  test('no backup is taken when the database is already current', () async {
    final file = await createEncryptedDatabase();
    final backup = await PreMigrationBackup.runIfNeeded(
      dbFile: file,
      hexKey: key,
      targetVersion: AppDatabase.currentSchemaVersion,
      backupsDir: Directory(p.join(tempDir.path, 'backups')),
    );
    expect(backup, isNull);
  });

  test('a backup is taken before an upgrade', () async {
    final file = await createEncryptedDatabase();
    final backup = await PreMigrationBackup.runIfNeeded(
      dbFile: file,
      hexKey: key,
      targetVersion: AppDatabase.currentSchemaVersion + 1,
      backupsDir: Directory(p.join(tempDir.path, 'backups')),
    );
    expect(backup, isNotNull);
    expect(backup!.existsSync(), isTrue);
  });
}
