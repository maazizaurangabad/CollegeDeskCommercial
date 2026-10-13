import '../security/secret_store.dart';

/// The backup password, kept in protected storage so automatic backups
/// can be made without asking. It is never shown again after it is set.
class BackupPasswordStore {
  BackupPasswordStore(this._store);

  final SecretStore _store;
  static const _key = 'sd.backup.password';

  Future<String?> read() => _store.read(_key);

  Future<void> write(String password) => _store.write(_key, password);

  static bool isStrongEnough(String password) => password.length >= 8;
}
