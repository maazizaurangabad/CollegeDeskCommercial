import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class BackupPasswordException implements Exception {
  const BackupPasswordException();
}

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Seals backup bytes with a password: AES-256-GCM with a key made from the
/// password by PBKDF2. GCM also proves the file is undamaged: a wrong
/// password or a changed byte both fail to open.
///
/// File layout: "SDBAK1" | salt (16) | nonce (12) | ciphertext | tag (16).
abstract final class BackupCodec {
  static final _magic = ascii.encode('SDBAK1');
  static const _iterations = 120000;

  static Future<Uint8List> seal(Uint8List plain, String password) {
    return Isolate.run(() async {
      final random = Random.secure();
      final salt = List<int>.generate(16, (_) => random.nextInt(256));
      final key = await _key(password, salt);
      final box = await AesGcm.with256bits().encrypt(plain, secretKey: key);
      final out = BytesBuilder(copy: false)
        ..add(_magic)
        ..add(salt)
        ..add(box.nonce)
        ..add(box.cipherText)
        ..add(box.mac.bytes);
      return out.toBytes();
    });
  }

  static Future<Uint8List> open(Uint8List sealed, String password) {
    return Isolate.run(() async {
      if (!isBackup(sealed)) throw const BackupFormatException('Not a Shiksha Desk backup file');
      final salt = sealed.sublist(6, 22);
      final nonce = sealed.sublist(22, 34);
      final cipherText = sealed.sublist(34, sealed.length - 16);
      final mac = Mac(sealed.sublist(sealed.length - 16));
      final key = await _key(password, salt);
      try {
        final plain = await AesGcm.with256bits().decrypt(SecretBox(cipherText, nonce: nonce, mac: mac), secretKey: key);
        return Uint8List.fromList(plain);
      } on SecretBoxAuthenticationError {
        throw const BackupPasswordException();
      }
    });
  }

  static bool isBackup(Uint8List bytes) {
    if (bytes.length < 6 + 16 + 12 + 16) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  static Future<SecretKey> _key(String password, List<int> salt) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);
}
