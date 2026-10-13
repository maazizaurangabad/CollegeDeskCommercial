import 'dart:convert';

/// Reads CSV text, including quoted cells with commas, quotes and line breaks.
abstract final class CsvReader {
  static List<List<String>> parse(List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final delimiter = _guessDelimiter(text);
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
        continue;
      }
      if (ch == '"') {
        inQuotes = true;
      } else if (ch == delimiter) {
        row.add(cell.toString().trim());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString().trim());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString().trim());
      rows.add(row);
    }
    final width = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    return [
      for (final r in rows)
        if (r.any((c) => c.isNotEmpty)) [...r, for (var i = r.length; i < width; i++) ''],
    ];
  }

  static String _guessDelimiter(String text) {
    final firstLine = text.split('\n').first;
    final counts = {',': ','.allMatches(firstLine).length, ';': ';'.allMatches(firstLine).length, '\t': '\t'.allMatches(firstLine).length};
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  static List<int> write(List<String> header, List<List<String>> rows) {
    String q(String s) => (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
    final text = [header, ...rows].map((r) => r.map(q).join(',')).join('\r\n');
    return [0xEF, 0xBB, 0xBF, ...utf8.encode(text)];
  }
}
