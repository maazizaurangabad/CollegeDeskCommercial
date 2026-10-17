import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'secret_store.dart';

/// The app PIN, the one-time recovery code, and lock settings.
/// Only salted, slow hashes are stored, never the PIN itself.
class PinLockStore {
  PinLockStore(this._store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final SecretStore _store;
  final DateTime Function() _clock;

  static const _pinKey = 'sd.lock.pin';
  static const _recoveryKey = 'sd.lock.recovery';
  static const _timeoutKey = 'sd.lock.timeout_minutes';
  static const _biometricKey = 'sd.lock.biometric';
  static const _failuresKey = 'sd.lock.failures';
  static const _blockedUntilKey = 'sd.lock.blocked_until';
  static const _lengthKey = 'sd.lock.pin_length';
  static const _biometricUserKey = 'sd.lock.biometric_user';

  static const freeAttempts = 5;
  static const defaultTimeoutMinutes = 5;

  final _pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 40000, bits: 256);

  Future<bool> hasPin() async => (await _store.read(_pinKey)) != null;

  static bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  /// Saves a new PIN and returns a new recovery code to show once.
  Future<String> setPin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be 4 to 6 digits');
    await _store.write(_pinKey, await _hash(pin));
    await _store.write(_lengthKey, '${pin.length}');
    final code = _newRecoveryCode();
    await _store.write(_recoveryKey, await _hash(_normalizeCode(code)));
    await _resetFailures();
    return code;
  }

  /// Changes the PIN and keeps the existing recovery code.
  Future<void> changePin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be 4 to 6 digits');
    await _store.write(_pinKey, await _hash(pin));
    await _store.write(_lengthKey, '${pin.length}');
    await _resetFailures();
  }

  /// How many digits the PIN has, so the lock screen checks it as soon as it is complete.
  Future<int> pinLength() async => int.tryParse(await _store.read(_lengthKey) ?? '') ?? 4;

  Future<void> removePin() async {
    await _store.delete(_pinKey);
    await _store.delete(_recoveryKey);
    await _store.delete(_lengthKey);
    await _resetFailures();
  }

  /// When attempts are blocked, the time they open again; otherwise null.
  Future<DateTime?> blockedUntil() async {
    final raw = await _store.read(_blockedUntilKey);
    final until = raw == null ? null : DateTime.tryParse(raw);
    return until != null && until.isAfter(_clock()) ? until : null;
  }

  /// True if [pin] is right. Wrong PINs after the first five make the
  /// user wait: 30 s, then 60 s, 120 s, and so on.
  Future<bool> verifyPin(String pin) async {
    if (await blockedUntil() != null) return false;
    final stored = await _store.read(_pinKey);
    if (stored == null) return true;
    final ok = await _matches(pin, stored);
    if (ok) {
      await _resetFailures();
    } else {
      final failures = int.parse(await _store.read(_failuresKey) ?? '0') + 1;
      await _store.write(_failuresKey, '$failures');
      if (failures >= freeAttempts) {
        final wait = Duration(seconds: 30 * (1 << min(failures - freeAttempts, 6)));
        await _store.write(_blockedUntilKey, _clock().add(wait).toIso8601String());
      }
    }
    return ok;
  }

  Future<bool> verifyRecoveryCode(String code) async {
    final stored = await _store.read(_recoveryKey);
    if (stored == null) return false;
    return _matches(_normalizeCode(code), stored);
  }

  Future<int> timeoutMinutes() async =>
      int.tryParse(await _store.read(_timeoutKey) ?? '') ?? defaultTimeoutMinutes;

  Future<void> setTimeoutMinutes(int minutes) => _store.write(_timeoutKey, '$minutes');

  Future<bool> biometricEnabled() async => (await _store.read(_biometricKey)) == 'true';

  Future<void> setBiometricEnabled(bool enabled) => _store.write(_biometricKey, '$enabled');

  /// The staff member the fingerprint logs in; null means the administrator.
  Future<String?> biometricUserId() async {
    final v = await _store.read(_biometricUserKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setBiometricUserId(String? id) => _store.write(_biometricUserKey, id ?? '');

  Future<void> _resetFailures() async {
    await _store.delete(_failuresKey);
    await _store.delete(_blockedUntilKey);
  }

  Future<String> _hash(String secret, [List<int>? salt]) async {
    final s = salt ?? List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final key = await _pbkdf2.deriveKeyFromPassword(password: secret, nonce: s);
    return '${base64Encode(s)}:${base64Encode(await key.extractBytes())}';
  }

  Future<bool> _matches(String secret, String stored) async {
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final again = await _hash(secret, base64Decode(parts[0]));
    return again == stored;
  }

  static String _normalizeCode(String code) => code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// 12 characters in groups of four, without easily confused letters.
  static String _newRecoveryCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final chars = List.generate(12, (_) => alphabet[r.nextInt(alphabet.length)]).join();
    return '${chars.substring(0, 4)}-${chars.substring(4, 8)}-${chars.substring(8)}';
  }
}
