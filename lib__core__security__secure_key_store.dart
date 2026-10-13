import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ids/uuid7.dart';

/// Keeps secrets in the operating system's protected storage
/// (Android Keystore, Windows Credential Manager). Never logged.
class SecureKeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _deviceIdKey = 'sd.device_id';
  static String _workspaceKeyName(String workspaceId) => 'sd.db_key.$workspaceId';
  static String _fieldKeyName(String workspaceId) => 'sd.field_key.$workspaceId';

  /// Used when restoring a backup: the institution keeps its own field key.
  Future<void> setFieldKey(String workspaceId, String hex) => _storage.write(key: _fieldKeyName(workspaceId), value: hex);

  /// Key for the second encryption layer (Aadhaar). Created on first need.
  Future<String> fieldKey(String workspaceId) async {
    final name = _fieldKeyName(workspaceId);
    final existing = await _storage.read(key: name);
    if (existing != null) return existing;
    final created = Uuid7.randomHex(64);
    await _storage.write(key: name, value: created);
    return created;
  }

  /// A permanent id for this installation.
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null) return existing;
    final created = Uuid7.generate();
    await _storage.write(key: _deviceIdKey, value: created);
    return created;
  }

  /// The encryption key for one institution's database.
  /// Only creates a new key when the database does not exist yet:
  /// a missing key for an existing database is reported, never replaced.
  Future<String?> workspaceKey(String workspaceId, {required bool createIfMissing}) async {
    final name = _workspaceKeyName(workspaceId);
    final existing = await _storage.read(key: name);
    if (existing != null) return existing;
    if (!createIfMissing) return null;
    final created = Uuid7.randomHex(32);
    await _storage.write(key: name, value: created);
    return created;
  }
}
