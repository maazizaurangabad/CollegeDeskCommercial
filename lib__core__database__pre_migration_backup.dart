import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Before an app update changes the database structure, copy the
/// current file aside so nothing can be lost if the upgrade fails.
abstract final class PreMigrationBackup {
  static Future<File?> runIfNeeded({
    required File dbFile,
    required String hexKey,
    required int targetVersion,
    required Directory backupsDir,
  }) async {
    if (!dbFile.existsSync()) return null;

    final int version;
    final raw = sqlite3.open(dbFile.path);
    try {
      raw.execute("PRAGMA key = '$hexKey';");
      version = raw.select('PRAGMA user_version;').first['user_version'] as int;
      if (version == 0 || version >= targetVersion) return null;
      raw.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } finally {
      raw.close();
    }

    await backupsDir.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final name = '${p.basenameWithoutExtension(dbFile.path)}.v$version-before-v$targetVersion.$stamp.db';
    return dbFile.copy(p.join(backupsDir.path, name));
  }
}
