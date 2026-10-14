/// Dates written in words, as certificates and leaving registers require:
/// 14 March 2010 -> "Fourteenth March Two Thousand Ten".
abstract final class DateWords {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _ordinals = [
    '', 'First', 'Second', 'Third', 'Fourth', 'Fifth', 'Sixth', 'Seventh', 'Eighth', 'Ninth', 'Tenth',
    'Eleventh', 'Twelfth', 'Thirteenth', 'Fourteenth', 'Fifteenth', 'Sixteenth', 'Seventeenth', 'Eighteenth',
    'Nineteenth', 'Twentieth', 'Twenty First', 'Twenty Second', 'Twenty Third', 'Twenty Fourth', 'Twenty Fifth',
    'Twenty Sixth', 'Twenty Seventh', 'Twenty Eighth', 'Twenty Ninth', 'Thirtieth', 'Thirty First',
  ];

  static const _ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve',
    'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
  ];

  static const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

  static String date(DateTime d) => '${_ordinals[d.day]} ${_months[d.month - 1]} ${year(d.year)}';

  /// 2010 -> "Two Thousand Ten"; 1998 -> "Nineteen Hundred Ninety Eight".
  static String year(int y) {
    if (y >= 2000) {
      final rest = y - 2000;
      return rest == 0 ? 'Two Thousand' : 'Two Thousand ${_below100(rest)}';
    }
    final hundreds = y ~/ 100;
    final rest = y % 100;
    return '${_below100(hundreds)} Hundred${rest == 0 ? '' : ' ${_below100(rest)}'}';
  }

  static String _below100(int n) {
    if (n < 20) return _ones[n];
    final t = _tens[n ~/ 10];
    return n % 10 == 0 ? t : '$t ${_ones[n % 10]}';
  }
}
