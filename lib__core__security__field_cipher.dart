import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Second layer of encryption for the most sensitive single values
/// (Aadhaar), inside the already-encrypted database. Also produces a
/// keyed fingerprint so duplicates can be found without decrypting.
class FieldCipher {
  FieldCipher(List<int> keyBytes)
      : assert(keyBytes.length == 64, 'FieldCipher needs 64 key bytes'),
        _encryptionKey = SecretKey(keyBytes.sublist(0, 32)),
        _fingerprintKey = SecretKey(keyBytes.sublist(32, 64));

  /// From the 128-character hex string kept in secure storage.
  factory FieldCipher.fromHex(String hex) {
    final bytes = <int>[for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
    return FieldCipher(bytes);
  }

  final SecretKey _encryptionKey;
  final SecretKey _fingerprintKey;
  final AesGcm _aes = AesGcm.with256bits();
  final Hmac _hmac = Hmac.sha256();

  Future<String> encrypt(String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: _encryptionKey);
    return base64Encode(box.concatenation());
  }

  Future<String> decrypt(String encoded) async {
    final box = SecretBox.fromConcatenation(
      base64Decode(encoded),
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    return utf8.decode(await _aes.decrypt(box, secretKey: _encryptionKey));
  }

  /// Same input always gives the same fingerprint; it cannot be reversed.
  Future<String> fingerprint(String plain) async {
    final mac = await _hmac.calculateMac(utf8.encode(plain), secretKey: _fingerprintKey);
    return base64Encode(mac.bytes);
  }
}
