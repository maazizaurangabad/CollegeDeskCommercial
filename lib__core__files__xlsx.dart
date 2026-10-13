import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// One sheet read from a workbook: every cell as text, rows padded to equal length.
class SheetTable {
  const SheetTable(this.name, this.rows);

  final String name;
  final List<List<String>> rows;
}

/// Reads .xlsx files directly (they are zip files of XML), so no
/// spreadsheet library is needed. Numbers stay as written, e.g. dates
/// arrive as Excel serial numbers and are converted by [FlexibleDate].
abstract final class XlsxReader {
  static List<String> sheetNames(List<int> bytes) => _workbook(bytes).sheets.map((s) => s.$1).toList();

  static SheetTable readSheet(List<int> bytes, int index) {
    final book = _workbook(bytes);
    final (name, path) = book.sheets[index];
    final file = book.archive.findFile(path);
    if (file == null) throw const FormatException('Sheet not found in the file');
    final doc = XmlDocument.parse(utf8.decode(file.content as List<int>));

    final cells = <int, Map<int, String>>{};
    var maxCol = -1;
    var maxRow = -1;
    var nextRow = 0;
    for (final row in doc.findAllElements('row')) {
      final rowRef = int.tryParse(row.getAttribute('r') ?? '');
      final r = (rowRef ?? (nextRow + 1)) - 1;
      nextRow = r + 1;
      var nextCol = 0;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? nextCol : _columnIndex(ref);
        nextCol = col + 1;
        final value = _cellText(c, book.sharedStrings).trim();
        if (value.isEmpty) continue;
        (cells[r] ??= {})[col] = value;
        if (col > maxCol) maxCol = col;
        if (r > maxRow) maxRow = r;
      }
    }
    final rows = <List<String>>[
      for (var r = 0; r <= maxRow; r++) [for (var c = 0; c <= maxCol; c++) cells[r]?[c] ?? ''],
    ];
    return SheetTable(name, rows);
  }

  static String _cellText(XmlElement c, List<String> shared) {
    final type = c.getAttribute('t');
    if (type == 'inlineStr') {
      return c.findAllElements('t').map((t) => t.innerText).join();
    }
    final v = c.getElement('v')?.innerText ?? '';
    switch (type) {
      case 's':
        final i = int.tryParse(v);
        return i == null || i >= shared.length ? '' : shared[i];
      case 'b':
        return v == '1' ? 'TRUE' : 'FALSE';
      default:
        // Whole numbers stored as 12.0 are shown as 12.
        if (v.endsWith('.0')) return v.substring(0, v.length - 2);
        return v;
    }
  }

  /// "C12" -> 2 (zero-based column).
  static int _columnIndex(String ref) {
    var col = 0;
    for (final unit in ref.codeUnits) {
      if (unit < 65 || unit > 90) break;
      col = col * 26 + (unit - 64);
    }
    return col - 1;
  }

  static _Workbook _workbook(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Not an .xlsx file');
    }
    String? read(String name) {
      final f = archive.findFile(name);
      return f == null ? null : utf8.decode(f.content as List<int>);
    }

    final workbookXml = read('xl/workbook.xml');
    if (workbookXml == null) throw const FormatException('Not an .xlsx file');
    final rels = <String, String>{};
    final relsXml = read('xl/_rels/workbook.xml.rels');
    if (relsXml != null) {
      for (final rel in XmlDocument.parse(relsXml).findAllElements('Relationship')) {
        final target = rel.getAttribute('Target') ?? '';
        rels[rel.getAttribute('Id') ?? ''] = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      }
    }
    final sheets = <(String, String)>[];
    var n = 1;
    for (final s in XmlDocument.parse(workbookXml).findAllElements('sheet')) {
      final relId = s.attributes.where((a) => a.name.local == 'id').map((a) => a.value).firstOrNull;
      sheets.add((s.getAttribute('name') ?? 'Sheet$n', rels[relId] ?? 'xl/worksheets/sheet$n.xml'));
      n++;
    }
    final shared = <String>[];
    final sharedXml = read('xl/sharedStrings.xml');
    if (sharedXml != null) {
      for (final si in XmlDocument.parse(sharedXml).findAllElements('si')) {
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }
    return _Workbook(archive, sheets, shared);
  }
}

class _Workbook {
  _Workbook(this.archive, this.sheets, this.sharedStrings);

  final Archive archive;
  final List<(String, String)> sheets;
  final List<String> sharedStrings;
}

/// Writes a simple one-sheet .xlsx: a bold header row and text cells.
abstract final class XlsxWriter {
  static List<int> write({required String sheetName, required List<String> header, required List<List<String>> rows}) {
    String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s).replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    String col(int i) {
      var n = i + 1;
      var s = '';
      while (n > 0) {
        final m = (n - 1) % 26;
        s = String.fromCharCode(65 + m) + s;
        n = (n - 1) ~/ 26;
      }
      return s;
    }

    final sheet = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
      ..write('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
      ..write('<sheetData>');
    final all = [header, ...rows];
    for (var r = 0; r < all.length; r++) {
      sheet.write('<row r="${r + 1}">');
      for (var c = 0; c < all[r].length; c++) {
        final style = r == 0 ? ' s="1"' : '';
        sheet.write('<c r="${col(c)}${r + 1}" t="inlineStr"$style><is><t xml:space="preserve">${esc(all[r][c])}</t></is></c>');
      }
      sheet.write('</row>');
    }
    sheet.write('</sheetData></worksheet>');

    final safeName = esc(sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName);
    final files = {
      '[Content_Types].xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
      '_rels/.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="$safeName" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
      'xl/styles.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf fontId="0"/><xf fontId="1" applyFont="1"/></cellXfs></styleSheet>',
      'xl/worksheets/sheet1.xml': sheet.toString(),
    };
    final archive = Archive();
    for (final e in files.entries) {
      final data = utf8.encode(e.value);
      archive.addFile(ArchiveFile(e.key, data.length, data));
    }
    return ZipEncoder().encode(archive)!;
  }
}
