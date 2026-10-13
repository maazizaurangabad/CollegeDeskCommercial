/// Reads the many ways dates are written in school sheets:
/// 14/03/2010, 14-3-2010, 14.03.10, 2010-03-14, and Excel serial numbers.
/// Day comes before month, as written in India.
abstract final class FlexibleDate {
  static DateTime? parse(String input, {DateTime? today}) {
    final s = input.trim();
    if (s.isEmpty) return null;

    // Excel stores dates as days since 30 Dec 1899.
    final serial = double.tryParse(s);
    if (serial != null) {
      if (serial < 1000 || serial > 80000) return null;
      final base = DateTime.utc(1899, 12, 30);
      final d = base.add(Duration(days: serial.floor()));
      return DateTime(d.year, d.month, d.day);
    }

    final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
    if (iso != null) return _build(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));

    final dmy = RegExp(r'^(\d{1,2})[-/. ](\d{1,2})[-/. ](\d{2,4})$').firstMatch(s);
    if (dmy != null) {
      var year = int.parse(dmy[3]!);
      if (dmy[3]!.length == 2) {
        final now = (today ?? DateTime.now()).year % 100;
        year += year <= now ? 2000 : 1900;
      }
      return _build(year, int.parse(dmy[2]!), int.parse(dmy[1]!));
    }

    final named = RegExp(r'^(\d{1,2})[-/ ]([A-Za-z]{3,})[-/ ,]*(\d{4})$').firstMatch(s);
    if (named != null) {
      const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
      final m = months.indexOf(named[2]!.substring(0, 3).toLowerCase());
      if (m >= 0) return _build(int.parse(named[3]!), m + 1, int.parse(named[1]!));
    }
    return null;
  }

  static DateTime? _build(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1900 || y > 2100) return null;
    final date = DateTime(y, m, d);
    return (date.month == m && date.day == d) ? date : null;
  }
}
