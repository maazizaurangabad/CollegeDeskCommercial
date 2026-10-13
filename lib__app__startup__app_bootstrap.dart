import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/backup/auto_backup.dart';
import '../../core/backup/backup_password_store.dart';
import '../../core/backup/backup_service.dart';
import '../../core/database/app_database.dart';
import '../../core/database/pre_migration_backup.dart';
import '../../core/security/field_cipher.dart';
import '../../core/security/secret_store.dart';
import '../../core/security/secure_key_store.dart';
import '../../core/session/app_session.dart';
import '../../platform/academic/academic_repository.dart';
import '../../platform/data/app_settings_repository.dart';
import '../../platform/data/module_settings_repository.dart';
import '../../platform/data/organization_repository.dart';
import '../../platform/demo/demo_data.dart';
import '../../platform/modules/module_registry.dart';
import '../../platform/organization/organization_profile.dart';
import '../../platform/workspace/institution_creator.dart';
import '../../platform/workspace/institution_draft.dart';
import '../../platform/workspace/workspace_registry.dart';
import '../../platform/workspace/workspace_seeder.dart';
import 'startup_state.dart';

/// Opens an institution's encrypted database before its first screen.
class AppBootstrap {
  static const themeModeKey = 'appearance.theme_mode';

  /// Single administrator until user accounts arrive in Phase 3.
  static const localAdminUserId = 'local-admin';

  /// Opens [workspaceId], or the last one used. Creates the demo
  /// institution the very first time the app runs.
  static Future<StartupState> open(ModuleRegistry registry, {String? workspaceId}) async {
    final env = await _Environment.load();
    var workspace = workspaceId == null ? env.workspaces.lastOpened : env.workspaces.byId(workspaceId);
    workspace ??= await env.workspaces.create(DemoData.organization.name, isDemo: true);
    await env.workspaces.setLastOpened(workspace.id);
    return _openWorkspace(env, workspace, registry);
  }

  /// Creates a real institution from the setup wizard and opens it.
  static Future<StartupState> createInstitution(ModuleRegistry registry, InstitutionDraft draft) async {
    final env = await _Environment.load();
    final workspace = await env.workspaces.create(draft.name.trim(), isDemo: false);
    try {
      return await _openWorkspace(env, workspace, registry, draft: draft);
    } catch (_) {
      // Undo: no half-created institution is left behind.
      await env.workspaces.remove(workspace.id);
      final file = File(p.join(env.supportDir.path, workspace.fileName));
      if (file.existsSync()) await file.delete();
      rethrow;
    }
  }

  static Future<List<WorkspaceInfo>> listWorkspaces() async {
    final env = await _Environment.load();
    return env.workspaces.workspaces;
  }

  static Future<void> renameWorkspace(String id, String name) async {
    final env = await _Environment.load();
    await env.workspaces.rename(id, name);
  }

  // ------------------------------------------------------------ backups

  static const lastSavedKey = 'backup.last_saved';

  static Future<BackupContents> readBackup(Uint8List bytes, String password) =>
      BackupService.open(bytes, password, currentSchemaVersion: AppDatabase.currentSchemaVersion);

  /// Makes a backup of the open institution with the saved backup password.
  static Future<Uint8List?> backupBytes(StartupState state) async {
    final password = await BackupPasswordStore(const DeviceSecretStore()).read();
    if (password == null) return null;
    return BackupService.create(
      db: state.database,
      organizationId: state.session.organizationId,
      organizationName: state.organization.name,
      isDemo: state.isDemo,
      mediaDir: state.mediaDir,
      password: password,
      fieldKeyHex: await SecureKeyStore().fieldKey(state.session.organizationId),
    );
  }

  /// Today's automatic backup, if not made yet. Old ones are pruned.
  static Future<void> runDailyBackup(StartupState state) async {
    final dir = AutoBackupPolicy.folderFor(await getApplicationSupportDirectory(), state.session.organizationId);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, AutoBackupPolicy.dailyName(DateTime.now())));
    if (!file.existsSync()) {
      final bytes = await backupBytes(state);
      if (bytes == null) return;
      await _writeAtomically(file, bytes);
    }
    final files = dir.listSync().whereType<File>().toList();
    final names = files.map((f) => p.basename(f.path)).toList();
    final modified = {for (final f in files) p.basename(f.path): f.lastModifiedSync()};
    for (final name in AutoBackupPolicy.toDelete(names, DateTime.now(), modified: modified)) {
      await File(p.join(dir.path, name)).delete();
    }
  }

  /// A safety backup just before something risky (import, restore).
  static Future<void> runBeforeBackup(StartupState state, String reason) async {
    final bytes = await backupBytes(state);
    if (bytes == null) return;
    final dir = AutoBackupPolicy.folderFor(await getApplicationSupportDirectory(), state.session.organizationId);
    await dir.create(recursive: true);
    await _writeAtomically(File(p.join(dir.path, AutoBackupPolicy.beforeName(reason, DateTime.now()))), bytes);
  }

  static Future<List<File>> listAutoBackups(String workspaceId) async {
    final dir = AutoBackupPolicy.folderFor(await getApplicationSupportDirectory(), workspaceId);
    if (!dir.existsSync()) return [];
    return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.sdbak')).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }

  static Future<void> _writeAtomically(File file, List<int> bytes) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  /// Rebuilds an institution from a backup beside the live files, then swaps
  /// them in. The replaced database and photos are kept in the backups folder.
  /// [beforeSwap] closes the open database when it is the same institution.
  static Future<StartupState> restore(
    ModuleRegistry registry,
    BackupContents contents, {
    required Future<void> Function(String organizationId) beforeSwap,
  }) async {
    final env = await _Environment.load();
    final id = contents.manifest.organizationId;
    final existing = env.workspaces.byId(id);
    final live = File(p.join(env.supportDir.path, existing?.fileName ?? 'org_$id.db'));
    final temp = File('${live.path}.restoring');
    await _deleteDbFiles(temp);
    final key = (await env.keys.workspaceKey(id, createIfMissing: true))!;

    final db = AppDatabase(AppDatabase.openEncrypted(temp, key));
    try {
      await db.customSelect('SELECT 1').get();
      await BackupService.writeInto(db, contents);
    } finally {
      await db.close();
    }
    final mediaLive = Directory(p.join(env.supportDir.path, 'media', id));
    final mediaTemp = Directory('${mediaLive.path}.restoring');
    if (mediaTemp.existsSync()) await mediaTemp.delete(recursive: true);
    await BackupService.writeMedia(mediaTemp, contents);

    await beforeSwap(id);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-').split('.').first;
    final safety = Directory(p.join(env.supportDir.path, 'backups', id));
    await safety.create(recursive: true);
    if (live.existsSync()) await live.rename(p.join(safety.path, 'before-restore-$stamp.db'));
    await _deleteDbFiles(live);
    await temp.rename(live.path);
    await _deleteDbFiles(temp);
    if (mediaLive.existsSync()) await mediaLive.rename(p.join(safety.path, 'media-before-restore-$stamp'));
    await mediaTemp.rename(mediaLive.path);

    final fieldKey = contents.manifest.fieldKeyHex;
    if (fieldKey != null) await env.keys.setFieldKey(id, fieldKey);
    final workspace = existing ??
        await env.workspaces.register(id: id, name: contents.manifest.organizationName, isDemo: contents.manifest.isDemo);
    await env.workspaces.setLastOpened(workspace.id);
    return _openWorkspace(env, workspace, registry);
  }

  /// Removes a database's leftover journal files (and the file itself for temp copies).
  static Future<void> _deleteDbFiles(File file) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('${file.path}$suffix');
      if (f.existsSync()) await f.delete();
    }
    if (file.path.endsWith('.restoring') && file.existsSync()) await file.delete();
  }

  /// The folder for one institution's files (logo now, documents later).
  static Future<Directory> mediaDirFor(String workspaceId) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'media', workspaceId));
    await dir.create(recursive: true);
    return dir;
  }

  /// Copies a picked logo into the institution's folder; returns the stored file name.
  static Future<String> storeLogo(Directory mediaDir, String sourcePath) async {
    final name = 'logo-${DateTime.now().millisecondsSinceEpoch}${p.extension(sourcePath).toLowerCase()}';
    await File(sourcePath).copy(p.join(mediaDir.path, name));
    return name;
  }

  static Future<StartupState> _openWorkspace(
    _Environment env,
    WorkspaceInfo workspace,
    ModuleRegistry registry, {
    InstitutionDraft? draft,
  }) async {
    final dbFile = File(p.join(env.supportDir.path, workspace.fileName));
    final key = await env.keys.workspaceKey(workspace.id, createIfMissing: !dbFile.existsSync());
    if (key == null) {
      throw const StartupException(
        'The encryption key for this institution is missing on this device. '
        'The data file has not been changed. Restore from a backup to continue.',
      );
    }

    await PreMigrationBackup.runIfNeeded(
      dbFile: dbFile,
      hexKey: key,
      targetVersion: AppDatabase.currentSchemaVersion,
      backupsDir: Directory(p.join(env.supportDir.path, 'backups', workspace.id)),
    );

    final db = AppDatabase(AppDatabase.openEncrypted(dbFile, key));
    final session = AppSession(organizationId: workspace.id, deviceId: env.deviceId, userId: localAdminUserId);
    final mediaDir = await mediaDirFor(workspace.id);
    final cipher = FieldCipher.fromHex(await env.keys.fieldKey(workspace.id));

    try {
      if (draft != null) {
        final logo = draft.logoSourcePath == null ? null : await storeLogo(mediaDir, draft.logoSourcePath!);
        await InstitutionCreator(db, session).create(
          profile: _profileFromDraft(workspace.id, draft, logo),
          yearLabel: draft.yearLabel.trim(),
          yearStart: draft.yearStart,
          yearEnd: draft.yearEnd,
          template: draft.template,
          registry: registry,
        );
      }
      return await loadState(
        db: db,
        session: session,
        registry: registry,
        encrypted: true,
        isDemo: workspace.isDemo,
        mediaDir: mediaDir,
        fieldCipher: cipher,
      );
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  /// Reads what the first screen needs (and seeds the demo institution).
  /// Shared by the app and by tests, which pass an in-memory database.
  static Future<StartupState> loadState({
    required AppDatabase db,
    required AppSession session,
    required ModuleRegistry registry,
    required bool encrypted,
    required FieldCipher fieldCipher,
    bool isDemo = true,
    Directory? mediaDir,
    int demoStudentCount = 500,
  }) async {
    if (isDemo) {
      await WorkspaceSeeder(db, session).seedDemoIfEmpty(registry, studentCount: demoStudentCount);
    }

    final organization = await OrganizationRepository(db, session).loadActive();
    if (organization == null) {
      throw const StartupException('The institution record could not be read.');
    }

    final saved = await ModuleSettingsRepository(db, session).loadAll();
    final enabled = {
      for (final m in registry.installed)
        if (m.isCore || (saved[m.id] ?? m.defaultEnabled)) m.id,
    };

    final themeName = await AppSettingsRepository(db, session).getValue(themeModeKey);
    final themeMode = ThemeMode.values.firstWhere((t) => t.name == themeName, orElse: () => ThemeMode.system);

    return StartupState(
      database: db,
      session: session,
      organization: organization,
      academic: await AcademicRepository(db, session).loadSnapshot(),
      enabledModules: enabled,
      themeMode: themeMode,
      encrypted: encrypted,
      isDemo: isDemo,
      fieldCipher: fieldCipher,
      mediaDir: mediaDir,
    );
  }

  static OrganizationProfile _profileFromDraft(String id, InstitutionDraft d, String? logoFileName) {
    String? opt(String v) => v.trim().isEmpty ? null : v.trim();
    return OrganizationProfile(
      id: id,
      name: d.name.trim(),
      shortName: d.shortName.trim().isEmpty ? d.name.trim() : d.shortName.trim(),
      institutionType: d.institutionType,
      city: d.city.trim(),
      activeAcademicYear: d.yearLabel.trim(),
      brandColor: d.brandColor,
      address: opt(d.address),
      state: opt(d.state),
      phone: opt(d.phone),
      email: opt(d.email),
      website: opt(d.website),
      board: opt(d.board),
      medium: opt(d.medium),
      udiseCode: opt(d.udiseCode),
      logoFileName: logoFileName,
    );
  }
}

class _Environment {
  _Environment(this.supportDir, this.keys, this.deviceId, this.workspaces);

  final Directory supportDir;
  final SecureKeyStore keys;
  final String deviceId;
  final WorkspaceRegistry workspaces;

  static Future<_Environment> load() async {
    final supportDir = await getApplicationSupportDirectory();
    final keys = SecureKeyStore();
    return _Environment(supportDir, keys, await keys.deviceId(), await WorkspaceRegistry.load(supportDir));
  }
}

class StartupException implements Exception {
  const StartupException(this.message);

  final String message;

  @override
  String toString() => message;
}
