import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import 'backup_codec.dart';

/// What a backup file says about itself.
class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.schemaVersion,
    required this.appVersion,
    required this.organizationId,
    required this.organizationName,
    required this.isDemo,
    required this.createdAt,
    required this.studentCount,
    required this.rowCounts,
    this.fieldKeyHex,
  });

  static const currentFormat = 1;

  final int formatVersion;
  final int schemaVersion;
  final String appVersion;
  final String organizationId;
  final String organizationName;
  final bool isDemo;
  final DateTime createdAt;
  final int studentCount;
  final Map<String, int> rowCounts;

  /// The key of the second encryption layer (Aadhaar). It travels inside the
  /// password-sealed backup so Aadhaar numbers open on a new device too.
  final String? fieldKeyHex;

  Map<String, Object?> toJson() => {
        'app': 'shiksha_desk',
        'formatVersion': formatVersion,
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
        'organizationId': organizationId,
        'organizationName': organizationName,
        'isDemo': isDemo,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'studentCount': studentCount,
        'rowCounts': rowCounts,
        if (fieldKeyHex != null) 'fieldKey': fieldKeyHex,
      };

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    if (json['app'] != 'shiksha_desk') throw const BackupFormatException('Not a Shiksha Desk backup');
    return BackupManifest(
      formatVersion: json['formatVersion'] as int,
      schemaVersion: json['schemaVersion'] as int,
      appVersion: json['appVersion'] as String? ?? '',
      organizationId: json['organizationId'] as String,
      organizationName: json['organizationName'] as String,
      isDemo: json['isDemo'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      studentCount: json['studentCount'] as int? ?? 0,
      rowCounts: (json['rowCounts'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, v as int)),
      fieldKeyHex: json['fieldKey'] as String?,
    );
  }
}

/// An opened backup, ready to inspect or restore.
class BackupContents {
  BackupContents(this.manifest, this.tables, this.media);

  final BackupManifest manifest;

  /// table name -> rows (column -> value)
  final Map<String, List<Map<String, Object?>>> tables;

  /// path inside the institution's media folder -> bytes
  final Map<String, List<int>> media;
}

class BackupTooNewException implements Exception {
  const BackupTooNewException(this.schemaVersion);

  final int schemaVersion;
}

/// Writes and reads .sdbak files. The data is saved table by table, so a
/// backup made by an older app version restores into a newer one: the new
/// database is created first and the old rows are copied into it.
abstract final class BackupService {
  static const appVersion = '0.6.0';
  static const fileExtension = 'sdbak';

  static Future<Uint8List> create({
    required AppDatabase db,
    required String organizationId,
    required String organizationName,
    required bool isDemo,
    required Directory? mediaDir,
    required String password,
    String? fieldKeyHex,
  }) async {
    final archive = Archive();
    final counts = <String, int>{};
    for (final table in db.allTables) {
      final name = table.actualTableName;
      final rows = await db.customSelect('SELECT * FROM "$name"').get();
      counts[name] = rows.length;
      final data = utf8.encode(jsonEncode(rows.map((r) => r.data).toList()));
      archive.addFile(ArchiveFile('data/$name.json', data.length, data));
    }
    final students = await db.customSelect(
      'SELECT count(*) AS c FROM students WHERE organization_id = ? AND deleted_at IS NULL',
      variables: [Variable.withString(organizationId)],
    ).getSingle();

    if (mediaDir != null && mediaDir.existsSync()) {
      for (final entity in mediaDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: mediaDir.path).replaceAll('\\', '/');
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile('media/$relative', bytes.length, bytes));
      }
    }

    final manifest = BackupManifest(
      formatVersion: BackupManifest.currentFormat,
      schemaVersion: db.schemaVersion,
      appVersion: appVersion,
      organizationId: organizationId,
      organizationName: organizationName,
      isDemo: isDemo,
      createdAt: DateTime.now().toUtc(),
      studentCount: students.read<int>('c'),
      rowCounts: counts,
      fieldKeyHex: fieldKeyHex,
    );
    final manifestBytes = utf8.encode(jsonEncode(manifest.toJson()));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);
    return BackupCodec.seal(zip, password);
  }

  /// Opens a backup. Throws [BackupPasswordException] for a wrong password
  /// or a damaged file, [BackupTooNewException] for a newer app's backup.
  static Future<BackupContents> open(Uint8List bytes, String password, {required int currentSchemaVersion}) async {
    final zip = await BackupCodec.open(bytes, password);
    final archive = ZipDecoder().decodeBytes(zip);
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) throw const BackupFormatException('The backup has no manifest');
    final manifest = BackupManifest.fromJson(
      jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>,
    );
    if (manifest.schemaVersion > currentSchemaVersion) throw BackupTooNewException(manifest.schemaVersion);

    final tables = <String, List<Map<String, Object?>>>{};
    final media = <String, List<int>>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      if (f.name.startsWith('data/') && f.name.endsWith('.json')) {
        final name = p.basenameWithoutExtension(f.name);
        final rows = jsonDecode(utf8.decode(f.content as List<int>)) as List<dynamic>;
        tables[name] = rows.map((r) => (r as Map<String, dynamic>).cast<String, Object?>()).toList();
        if (tables[name]!.length != (manifest.rowCounts[name] ?? tables[name]!.length)) {
          throw const BackupFormatException('The backup is incomplete');
        }
      } else if (f.name.startsWith('media/')) {
        media[f.name.substring('media/'.length)] = f.content as List<int>;
      }
    }
    return BackupContents(manifest, tables, media);
  }

  /// Copies the backup's rows into an empty database of the current version.
  /// Columns the backup does not have are left at their defaults.
  static Future<void> writeInto(AppDatabase target, BackupContents contents) async {
    await target.transaction(() async {
      for (final table in target.allTables) {
        final name = table.actualTableName;
        final rows = contents.tables[name];
        if (rows == null || rows.isEmpty) continue;
        final columns = (await target.customSelect('PRAGMA table_info("$name")').get())
            .map((r) => r.read<String>('name'))
            .toSet();
        await target.customStatement('DELETE FROM "$name"');
        for (final row in rows) {
          final keys = row.keys.where(columns.contains).toList();
          if (keys.isEmpty) continue;
          final sql = 'INSERT INTO "$name" (${keys.map((k) => '"$k"').join(', ')}) '
              'VALUES (${List.filled(keys.length, '?').join(', ')})';
          await target.customStatement(sql, [for (final k in keys) row[k]]);
        }
      }
    });
  }

  /// Writes the backup's photos and logo into an institution's media folder.
  static Future<void> writeMedia(Directory mediaDir, BackupContents contents) async {
    await mediaDir.create(recursive: true);
    for (final entry in contents.media.entries) {
      final safe = p.normalize(entry.key);
      if (p.isAbsolute(safe) || safe.startsWith('..')) continue;
      final file = File(p.join(mediaDir.path, safe));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value, flush: true);
    }
  }
}
