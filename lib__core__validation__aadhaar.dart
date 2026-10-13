/// Aadhaar numbers: 12 digits, first digit 2-9, last digit a Verhoeff checksum.
/// The checksum catches almost every single typing mistake and swapped pair.
abstract final class Aadhaar {
  static const _d = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
    [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
    [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
    [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
    [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
    [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
    [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
    [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
    [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
  ];

  static const _p = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
    [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
    [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
    [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
    [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
    [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
    [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
  ];

  static const _inv = [0, 4, 3, 2, 1, 5, 6, 7, 8, 9];

  /// Removes spaces and dashes.
  static String normalize(String input) => input.replaceAll(RegExp(r'[\s-]'), '');

  static bool isValid(String input) {
    final digits = normalize(input);
    if (!RegExp(r'^[2-9][0-9]{11}$').hasMatch(digits)) return false;
    var c = 0;
    final reversed = digits.split('').reversed.map(int.parse).toList();
    for (var i = 0; i < reversed.length; i++) {
      c = _d[c][_p[i % 8][reversed[i]]];
    }
    return c == 0;
  }

  /// Computes the check digit for the first 11 digits (used by tests and demo data).
  static int checkDigit(String elevenDigits) {
    var c = 0;
    final reversed = elevenDigits.split('').reversed.map(int.parse).toList();
    for (var i = 0; i < reversed.length; i++) {
      c = _d[c][_p[(i + 1) % 8][reversed[i]]];
    }
    return _inv[c];
  }

  /// XXXX XXXX 1234
  static String mask(String lastFour) => 'XXXX XXXX $lastFour';

  /// 1234 5678 9012
  static String format(String input) {
    final d = normalize(input);
    if (d.length != 12) return d;
    return '${d.substring(0, 4)} ${d.substring(4, 8)} ${d.substring(8)}';
  }
}
