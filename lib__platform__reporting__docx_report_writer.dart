import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/files/image_size.dart';
import 'pdf_report_renderer.dart';
import 'report_dataset.dart';

/// A report as an editable Word document (.docx): the letterhead, title,
/// a table whose heading repeats on every page, photos inside their cells,
/// the notes and signature lines. A4, portrait or landscape like the PDF.
abstract final class DocxReportWriter {
  static const _emuPerPoint = 12700;

  static Uint8List write(ReportDataset data, ReportLetterhead head) {
    final media = <String, Uint8List>{}; // file name -> bytes
    final mediaRel = <String, String>{}; // file name -> relationship id
    var drawingId = 0;

    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    String hex(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    final brand = hex(head.brandColor);
    final size = (data.fontSize * 2).round(); // half-points

    String run(String text, {int? halfPoints, bool bold = false, String? color, bool italic = false}) =>
        '<w:r><w:rPr>${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}'
        '${color == null ? '' : '<w:color w:val="$color"/>'}'
        '<w:sz w:val="${halfPoints ?? size}"/><w:szCs w:val="${halfPoints ?? size}"/></w:rPr>'
        '<w:t xml:space="preserve">${esc(text)}</w:t></w:r>';

    String paragraph(String runs, {String align = 'left', int after = 0, int before = 0}) =>
        '<w:p><w:pPr><w:spacing w:before="$before" w:after="$after"/><w:jc w:val="$align"/></w:pPr>$runs</w:p>';

    /// An inline picture [width] × [height] points.
    String picture(Uint8List bytes, double width, double height) {
      final kind = imageKind(bytes) ?? 'jpeg';
      final name = 'image${media.length + 1}.${kind == 'png' ? 'png' : 'jpeg'}';
      media[name] = bytes;
      final rel = 'rIdImg${media.length}';
      mediaRel[name] = rel;
      drawingId++;
      final cx = (width * _emuPerPoint).round(), cy = (height * _emuPerPoint).round();
      return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
          '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$drawingId" name="Picture $drawingId"/>'
          '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
          '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
          '<pic:pic><pic:nvPicPr><pic:cNvPr id="$drawingId" name="$name"/><pic:cNvPicPr/></pic:nvPicPr>'
          '<pic:blipFill><a:blip r:embed="$rel"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
          '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
          '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
          '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
    }

    // Page: A4 with 0.5 inch margins (sizes in twentieths of a point).
    final pageW = data.landscape ? 16838 : 11906, pageH = data.landscape ? 11906 : 16838;
    const margin = 720;
    final usable = pageW - 2 * margin;

    // Column widths: fixed ones as given, the rest share what is left.
    final fixed = data.columns.fold<double>(0, (s, c) => s + (c.width ?? 0)) * 20;
    final flex = data.columns.fold<double>(0, (s, c) => s + (c.width == null ? (c.flex ?? 1) : 0));
    final spare = usable - fixed;
    var widths = [
      for (final c in data.columns) c.width != null ? c.width! * 20 : (flex == 0 ? 0.0 : spare * (c.flex ?? 1) / flex),
    ];
    final total = widths.fold<double>(0, (s, w) => s + w);
    if (spare < 0 || flex == 0) widths = [for (final w in widths) w * usable / (total == 0 ? 1 : total)];
    final grid = [for (final w in widths) w.round().clamp(200, usable).toInt()];

    String align(ReportAlign a) => switch (a) {
          ReportAlign.left => 'left',
          ReportAlign.center => 'center',
          ReportAlign.right => 'right',
        };

    String cell(int col, String content, {String? fill, int span = 1, int? width}) =>
        '<w:tc><w:tcPr><w:tcW w:w="${width ?? grid[col]}" w:type="dxa"/>'
        '${span > 1 ? '<w:gridSpan w:val="$span"/>' : ''}'
        '${fill == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>'}'
        '<w:vAlign w:val="center"/></w:tcPr>$content</w:tc>';

    final body = StringBuffer();

    // Letterhead.
    final logo = head.logo;
    body.write(paragraph(
      '${logo != null && imageKind(logo) != null ? picture(logo, 42, 42) : ''}'
      '${run(logo != null && imageKind(logo) != null ? '  ${head.name}' : head.name, halfPoints: 30, bold: true, color: brand)}',
    ));
    for (final line in head.lines) {
      body.write(paragraph(run(line, halfPoints: 17, color: '5B6470')));
    }
    body.write('<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="8" w:space="1" w:color="$brand"/></w:pBdr>'
        '<w:spacing w:before="0" w:after="120"/></w:pPr></w:p>');

    // Title and subtitle.
    body.write(paragraph(run(data.title, halfPoints: 26, bold: true), align: 'center', after: 40));
    for (final s in data.subtitle.where((s) => s.trim().isNotEmpty)) {
      body.write(paragraph(run(s, halfPoints: 18, color: '5B6470'), align: 'center'));
    }
    body.write(paragraph('', after: 80));

    // The table.
    const line = 'C9CED6';
    body
      ..write('<w:tbl><w:tblPr><w:tblW w:w="${grid.fold<int>(0, (s, w) => s + w)}" w:type="dxa"/>'
          '<w:tblLayout w:type="fixed"/><w:tblBorders>')
      ..write(['top', 'left', 'bottom', 'right', 'insideH', 'insideV']
          .map((b) => '<w:$b w:val="single" w:sz="4" w:space="0" w:color="$line"/>')
          .join())
      ..write('</w:tblBorders><w:tblCellMar><w:top w:w="30" w:type="dxa"/><w:left w:w="70" w:type="dxa"/>'
          '<w:bottom w:w="30" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>')
      ..write(grid.map((w) => '<w:gridCol w:w="$w"/>').join())
      ..write('</w:tblGrid>');

    // Heading row, repeated on every page.
    body.write('<w:tr><w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>');
    for (var i = 0; i < data.columns.length; i++) {
      body.write(cell(
        i,
        paragraph(run(data.columns[i].label, bold: true, color: 'FFFFFF'), align: 'center'),
        fill: brand,
      ));
    }
    body.write('</w:tr>');

    final imageBoxH = data.imageHeight, imageBoxW = data.imageHeight * 0.8;
    var dataIndex = 0;
    for (final r in data.rows) {
      if (r.kind == ReportRowKind.group) {
        body
          ..write('<w:tr><w:trPr><w:cantSplit/></w:trPr>')
          ..write(cell(
            0,
            paragraph(run(r.groupTitle ?? '', bold: true, color: brand)),
            fill: 'E8EEF6',
            span: data.columns.length,
            width: grid.fold<int>(0, (s, w) => s + w),
          ))
          ..write('</w:tr>');
        continue;
      }
      final striped = data.zebra && (dataIndex++).isOdd;
      final fill = r.highlight ? 'FFF4E5' : (striped ? 'F2F5F9' : null);
      final tall = data.imageColumns.isNotEmpty;
      body.write('<w:tr><w:trPr><w:cantSplit/>'
          '${tall ? '<w:trHeight w:val="${((imageBoxH + 8) * 20).round()}" w:hRule="atLeast"/>' : ''}</w:trPr>');
      for (var i = 0; i < data.columns.length; i++) {
        final text = i < r.cells.length ? r.cells[i] : '';
        final String content;
        if (data.imageColumns.contains(i)) {
          final bytes = r.images[i];
          if (bytes != null && imageKind(bytes) != null) {
            final fit = fitInBox(imagePixelSize(bytes), imageBoxW, imageBoxH);
            content = paragraph(picture(bytes, fit.width, fit.height), align: 'center');
          } else {
            content = paragraph(run(text, color: '8A929C', halfPoints: size - 3), align: 'center');
          }
        } else {
          final color = r.textColors[i];
          content = paragraph(
            run(text, bold: r.kind == ReportRowKind.total, color: color == null ? null : hex(color)),
            align: align(data.columns[i].align),
          );
        }
        body.write(cell(i, content, fill: fill));
      }
      body.write('</w:tr>');
    }
    body.write('</w:tbl>');

    // Notes and signatures.
    for (final n in data.notes) {
      body.write(paragraph(run(n, halfPoints: 18, color: '5B6470'), before: 80));
    }
    if (data.signatures.isNotEmpty) {
      final w = (usable / data.signatures.length).floor();
      body
        ..write('<w:tbl><w:tblPr><w:tblW w:w="${w * data.signatures.length}" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
            '<w:tblBorders><w:top w:val="nil"/><w:left w:val="nil"/><w:bottom w:val="nil"/><w:right w:val="nil"/>'
            '<w:insideH w:val="nil"/><w:insideV w:val="nil"/></w:tblBorders></w:tblPr><w:tblGrid>')
        ..write(List.filled(data.signatures.length, '<w:gridCol w:w="$w"/>').join())
        ..write('</w:tblGrid><w:tr>');
      for (final s in data.signatures) {
        body.write('<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/></w:tcPr>'
            '${paragraph(run('____________________'), align: 'center', before: 900)}'
            '${paragraph(run(s, halfPoints: 18), align: 'center')}</w:tc>');
      }
      body.write('</w:tr></w:tbl>');
    }

    body.write('<w:sectPr><w:pgSz w:w="$pageW" w:h="$pageH"${data.landscape ? ' w:orient="landscape"' : ''}/>'
        '<w:pgMar w:top="$margin" w:right="$margin" w:bottom="$margin" w:left="$margin" '
        'w:header="360" w:footer="360" w:gutter="0"/></w:sectPr>');

    final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$body</w:body></w:document>';

    final styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri" w:eastAsia="Calibri"/>'
        '<w:sz w:val="$size"/><w:szCs w:val="$size"/><w:lang w:val="en-IN"/></w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
        '</w:styles>';

    final rels = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
    for (final e in mediaRel.entries) {
      rels.write('<Relationship Id="${e.value}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${e.key}"/>');
    }
    rels.write('</Relationships>');

    final files = <String, List<int>>{
      '[Content_Types].xml': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Default Extension="jpeg" ContentType="image/jpeg"/>'
          '<Default Extension="png" ContentType="image/png"/>'
          '<Override PartName="/word/document.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          '</Types>'),
      '_rels/.rels': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
          'Target="word/document.xml"/></Relationships>'),
      'word/document.xml': utf8.encode(document),
      'word/styles.xml': utf8.encode(styles),
      'word/_rels/document.xml.rels': utf8.encode(rels.toString()),
      for (final e in media.entries) 'word/media/${e.key}': e.value,
    };
    final archive = Archive();
    for (final e in files.entries) {
      archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }
}
