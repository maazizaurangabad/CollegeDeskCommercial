import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Salted, slow PIN hashes ("salt:hash"), the same way as the app PIN.
class PinHasher {
  PinHasher({int iterations = 40000}) : _pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);

  final Pbkdf2 _pbkdf2;

  static bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  Future<String> hash(String pin, [List<int>? salt]) async {
    final s = salt ?? List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final key = await _pbkdf2.deriveKeyFromPassword(password: pin, nonce: s);
    return '${base64Encode(s)}:${base64Encode(await key.extractBytes())}';
  }

  Future<bool> matches(String pin, String? stored) async {
    if (stored == null) return false;
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    try {
      return await hash(pin, base64Decode(parts[0])) == stored;
    } catch (_) {
      return false;
    }
  }
}
