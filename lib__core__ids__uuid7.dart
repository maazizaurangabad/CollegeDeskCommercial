import 'dart:math';
import 'dart:typed_data';

/// UUID version 7: time-ordered, random, safe to create offline on many
/// devices at once without collisions. Used as every record's permanent id.
abstract final class Uuid7 {
  static final Random _random = Random.secure();

  static String generate([DateTime? now]) {
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final bytes = Uint8List(16);
    var t = ms;
    for (var i = 5; i >= 0; i--) {
      bytes[i] = t & 0xff;
      t = t ~/ 256;
    }
    for (var i = 6; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x70; // version 7
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Random hex string, used for encryption keys.
  static String randomHex(int byteCount) {
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
