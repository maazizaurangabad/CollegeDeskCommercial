import 'dart:convert';

import 'package:archive/archive.dart';

enum XlsxCellType { text, number, date }

/// A formatted one-sheet workbook: heading lines, a coloured and frozen
/// header row with Excel filter buttons, sized columns, borders, alternate
/// row shading, real numbers and dates, and print settings (fit to page
/// width, header repeated on every printed page).
abstract final class XlsxStyledWriter {
  // Style ids in styles.xml (cellXfs order).
  static const _title = 1;
  static const _subtitle = 2;
  static const _header = 3;
  static const _cell = 4;
  static const _cellAlt = 5;
  static const _number = 6;
  static const _numberAlt = 7;
  static const _date = 8;
  static const _dateAlt = 9;
  static const _note = 10;

  static List<int> write({
    required String sheetName,
    required List<String> headingLines,
    required List<String> header,
    required List<List<String>> rows,
    List<XlsxCellType>? types,
    List<String> notes = const [],
    bool landscape = false,
    int brandColor = 0xFF1D4E89,
  }) {
    String esc(String s) =>
        const HtmlEscape(HtmlEscapeMode.element).convert(s).replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
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

    final colTypes = types ?? List.filled(header.length, XlsxCellType.text);
    final lastCol = col(header.length - 1);
    final headerRow = headingLines.length + 2; // one blank row after the headings
    final firstData = headerRow + 1;
    final lastData = headerRow + rows.length;

    // Column widths from the longest value (in characters), within limits.
    final widths = <double>[
      for (var c = 0; c < header.length; c++)
        ([
                  header[c].length + 2,
                  for (final r in rows.take(500)) (c < r.length ? r[c].length : 0) + 2,
                ].reduce((a, b) => a > b ? a : b))
            .clamp(6, 45)
            .toDouble(),
    ];

    final sb = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
      ..write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>')
      ..write('<sheetViews><sheetView workbookViewId="0">'
          '<pane ySplit="$headerRow" topLeftCell="A$firstData" activePane="bottomLeft" state="frozen"/>'
          '</sheetView></sheetViews>')
      ..write('<sheetFormatPr defaultRowHeight="16"/>')
      ..write('<cols>');
    for (var c = 0; c < widths.length; c++) {
      sb.write('<col min="${c + 1}" max="${c + 1}" width="${widths[c]}" customWidth="1"/>');
    }
    sb.write('</cols><sheetData>');

    void text(int r, int c, String v, int style) =>
        sb.write('<c r="${col(c)}$r" t="inlineStr" s="$style"><is><t xml:space="preserve">${esc(v)}</t></is></c>');

    for (var i = 0; i < headingLines.length; i++) {
      sb.write('<row r="${i + 1}" ht="${i == 0 ? 22 : 16}" customHeight="1">');
      text(i + 1, 0, headingLines[i], i == 0 ? _title : _subtitle);
      sb.write('</row>');
    }
    sb.write('<row r="$headerRow" ht="20" customHeight="1">');
    for (var c = 0; c < header.length; c++) {
      text(headerRow, c, header[c], _header);
    }
    sb.write('</row>');

    for (var i = 0; i < rows.length; i++) {
      final r = firstData + i;
      final alt = i.isOdd;
      sb.write('<row r="$r">');
      for (var c = 0; c < header.length; c++) {
        final v = c < rows[i].length ? rows[i][c] : '';
        final type = c < colTypes.length ? colTypes[c] : XlsxCellType.text;
        final number = type == XlsxCellType.number ? num.tryParse(v.replaceAll('%', '')) : null;
        final serial = type == XlsxCellType.date ? _dateSerial(v) : null;
        if (number != null) {
          sb.write('<c r="${col(c)}$r" s="${alt ? _numberAlt : _number}"><v>$number</v></c>');
        } else if (serial != null) {
          sb.write('<c r="${col(c)}$r" s="${alt ? _dateAlt : _date}"><v>$serial</v></c>');
        } else {
          text(r, c, v, alt ? _cellAlt : _cell);
        }
      }
      sb.write('</row>');
    }
    for (var i = 0; i < notes.length; i++) {
      final r = lastData + 2 + i;
      sb.write('<row r="$r">');
      text(r, 0, notes[i], _note);
      sb.write('</row>');
    }
    sb.write('</sheetData>');
    if (rows.isNotEmpty) sb.write('<autoFilter ref="A$headerRow:$lastCol$lastData"/>');
    sb
      ..write('<printOptions horizontalCentered="1"/>')
      ..write('<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>')
      ..write('<pageSetup paperSize="9" orientation="${landscape ? 'landscape' : 'portrait'}" fitToWidth="1" fitToHeight="0"/>')
      ..write('<headerFooter><oddFooter>&amp;LPage &amp;P of &amp;N&amp;R${esc(sheetName)}</oddFooter></headerFooter>')
      ..write('</worksheet>');

    final safeName = esc((sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName).replaceAll(RegExp(r"[\[\]:*?/\\']"), ' '));
    final quoted = "'${safeName.replaceAll("'", "''")}'";
    final brandHex = (brandColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

    final styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/></numFmts>'
        '<fonts count="5">'
        '<font><sz val="10.5"/><name val="Calibri"/></font>'
        '<font><b/><sz val="14"/><color rgb="FF$brandHex"/><name val="Calibri"/></font>'
        '<font><sz val="10.5"/><color rgb="FF5B6470"/><name val="Calibri"/></font>'
        '<font><b/><sz val="10.5"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
        '<font><i/><sz val="10"/><color rgb="FF5B6470"/><name val="Calibri"/></font>'
        '</fonts>'
        '<fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FF$brandHex"/><bgColor indexed="64"/></patternFill></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFF2F5F9"/><bgColor indexed="64"/></patternFill></fill>'
        '</fills>'
        '<borders count="2"><border/>'
        '<border><left style="thin"><color rgb="FFD5DAE0"/></left><right style="thin"><color rgb="FFD5DAE0"/></right>'
        '<top style="thin"><color rgb="FFD5DAE0"/></top><bottom style="thin"><color rgb="FFD5DAE0"/></bottom></border>'
        '</borders>'
        '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
        '<cellXfs count="11">'
        '<xf fontId="0"/>'
        '<xf fontId="1" applyFont="1"/>'
        '<xf fontId="2" applyFont="1"/>'
        '<xf fontId="3" fillId="2" borderId="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'
        '<xf fontId="0" borderId="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>'
        '<xf fontId="0" fillId="3" borderId="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>'
        '<xf fontId="0" borderId="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
        '<xf fontId="0" fillId="3" borderId="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
        '<xf numFmtId="164" fontId="0" borderId="1" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
        '<xf numFmtId="164" fontId="0" fillId="3" borderId="1" applyNumberFormat="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
        '<xf fontId="4" applyFont="1"/>'
        '</cellXfs></styleSheet>';

    final files = {
      '[Content_Types].xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
      '_rels/.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
              '<sheets><sheet name="$safeName" sheetId="1" r:id="rId1"/></sheets>'
              '<definedNames>'
              '${rows.isEmpty ? '' : '<definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">$quoted!\$A\$$headerRow:\$$lastCol\$$lastData</definedName>'}'
              '<definedName name="_xlnm.Print_Titles" localSheetId="0">$quoted!\$$headerRow:\$$headerRow</definedName>'
              '</definedNames></workbook>',
      'xl/_rels/workbook.xml.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
      'xl/styles.xml': styles,
      'xl/worksheets/sheet1.xml': sb.toString(),
    };
    final archive = Archive();
    for (final e in files.entries) {
      final data = utf8.encode(e.value);
      archive.addFile(ArchiveFile(e.key, data.length, data));
    }
    return ZipEncoder().encode(archive)!;
  }

  /// "14/03/2010" or "2010-03-14" -> Excel date serial; null if not a date.
  static int? _dateSerial(String v) {
    final s = v.trim();
    DateTime? d;
    final dmy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (dmy != null) {
      d = DateTime.utc(int.parse(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!));
    } else if (iso != null) {
      d = DateTime.utc(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    }
    if (d == null) return null;
    return d.difference(DateTime.utc(1899, 12, 30)).inDays;
  }
}
