/// Indian mobile numbers: 10 digits starting 6-9, optional +91 or 0 prefix.
abstract final class MobileNumber {
  static String normalize(String input) {
    var d = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    return d;
  }

  static bool isValid(String input) => RegExp(r'^[6-9][0-9]{9}$').hasMatch(normalize(input));
}
