import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_dataset.dart';

/// The institution's heading on every page.
class ReportLetterhead {
  const ReportLetterhead({required this.name, this.lines = const [], this.logo, this.brandColor = 0xFF1D4E89});

  final String name;

  /// Address, phone, UDISE and similar, one per line.
  final List<String> lines;
  final Uint8List? logo;
  final int brandColor;
}

class ReportFonts {
  const ReportFonts(this.regular, this.bold);

  final ByteData regular;
  final ByteData bold;
}

/// Draws any [ReportDataset] as an A4 PDF: letterhead on every page, the
/// table split into pages with its header repeated, page numbers, and
/// signature lines at the end.
abstract final class PdfReportRenderer {
  static Future<Uint8List> render(
    ReportDataset data,
    ReportLetterhead head,
    ReportFonts fonts, {
    DateTime? generatedOn,
    String generatedBy = 'Shiksha Desk',
  }) async {
    final regular = pw.Font.ttf(fonts.regular);
    final bold = pw.Font.ttf(fonts.bold);
    final brand = PdfColor.fromInt(head.brandColor);
    final line = PdfColor.fromInt(0xFFBFC5CC);
    final shade = PdfColor.fromInt(0xFFEEF1F4);
    final warn = PdfColor.fromInt(0xFFFDECEC);
    final format = data.landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    final fs = data.fontSize;
    final logo = head.logo == null ? null : pw.MemoryImage(head.logo!);
    final stamp = DateFormat('d MMM y, h:mm a').format(generatedOn ?? DateTime.now());

    final doc = pw.Document(title: data.title, author: head.name, creator: generatedBy);

    // Rows per page, estimated from the page height, so each page gets its own header row.
    final usable = format.height - 36 * 2 - 92 - 30;
    final rowHeight = fs * 1.9 + 2;
    final perPage = ((usable / rowHeight).floor() - 1).clamp(8, 200).toInt();

    pw.Alignment align(ReportAlign a) => switch (a) {
          ReportAlign.left => pw.Alignment.centerLeft,
          ReportAlign.center => pw.Alignment.center,
          ReportAlign.right => pw.Alignment.centerRight,
        };

    final widths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < data.columns.length; i++)
        i: data.columns[i].width != null
            ? pw.FixedColumnWidth(data.columns[i].width!)
            : pw.FlexColumnWidth(data.columns[i].flex ?? 1),
    };

    pw.Widget cell(String text, int col, {bool header = false, PdfColor? color, PdfColor? fill}) => pw.Container(
          alignment: header ? pw.Alignment.center : align(data.columns[col].align),
          color: fill,
          padding: const pw.EdgeInsets.symmetric(horizontal: 2.5, vertical: 2),
          child: pw.Text(
            text,
            maxLines: 2,
            style: pw.TextStyle(
              font: header ? bold : regular,
              fontSize: header ? fs - 0.5 : fs,
              color: header ? PdfColors.white : (color ?? PdfColors.black),
            ),
          ),
        );

    pw.TableRow headerRow() => pw.TableRow(
          decoration: pw.BoxDecoration(color: brand),
          children: [for (var i = 0; i < data.columns.length; i++) cell(data.columns[i].label, i, header: true)],
        );

    pw.TableRow toRow(ReportRow r) {
      if (r.kind == ReportRowKind.group) {
        return pw.TableRow(
          decoration: pw.BoxDecoration(color: shade),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
              child: pw.Text(r.groupTitle ?? '', style: pw.TextStyle(font: bold, fontSize: fs)),
            ),
            for (var i = 1; i < data.columns.length; i++) pw.SizedBox(),
          ],
        );
      }
      return pw.TableRow(
        decoration: r.highlight ? pw.BoxDecoration(color: warn) : null,
        children: [
          for (var i = 0; i < data.columns.length; i++)
            cell(
              i < r.cells.length ? r.cells[i] : '',
              i,
              color: r.textColors[i] == null ? null : PdfColor.fromInt(r.textColors[i]!),
              fill: data.shadedColumns.contains(i) && !r.highlight ? shade : null,
            ),
        ],
      );
    }

    final chunks = <List<ReportRow>>[];
    for (var i = 0; i < data.rows.length; i += perPage) {
      chunks.add(data.rows.sublist(i, i + perPage > data.rows.length ? data.rows.length : i + perPage));
    }
    if (chunks.isEmpty) chunks.add(const []);

    pw.Widget header(pw.Context context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: brand, width: 1.5))),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null) ...[
                pw.SizedBox(width: 44, height: 44, child: pw.Image(logo, fit: pw.BoxFit.contain)),
                pw.SizedBox(width: 10),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(head.name, style: pw.TextStyle(font: bold, fontSize: 14, color: brand)),
                    for (final l in head.lines.where((l) => l.trim().isNotEmpty))
                      pw.Text(l, style: pw.TextStyle(font: regular, fontSize: 8.5, color: PdfColors.grey700)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(data.title, style: pw.TextStyle(font: bold, fontSize: 12)),
                  for (final s in data.subtitle) pw.Text(s, style: pw.TextStyle(font: regular, fontSize: 9)),
                ],
              ),
            ],
          ),
        );

    pw.Widget footer(pw.Context context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated on $stamp by $generatedBy',
                style: pw.TextStyle(font: regular, fontSize: 7.5, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(font: regular, fontSize: 7.5, color: PdfColors.grey600)),
          ],
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: header,
        footer: footer,
        build: (context) => [
          for (var c = 0; c < chunks.length; c++) ...[
            pw.Table(
              border: pw.TableBorder.all(color: line, width: 0.5),
              columnWidths: widths,
              children: [headerRow(), for (final r in chunks[c]) toRow(r)],
            ),
            if (c < chunks.length - 1) pw.NewPage(),
          ],
          if (data.notes.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            for (final n in data.notes) pw.Text(n, style: pw.TextStyle(font: regular, fontSize: 8.5)),
          ],
          if (data.signatures.isNotEmpty) ...[
            pw.SizedBox(height: 40),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                for (final s in data.signatures)
                  pw.Column(children: [
                    pw.Container(width: 140, height: 0.7, color: PdfColors.grey700),
                    pw.SizedBox(height: 3),
                    pw.Text(s, style: pw.TextStyle(font: regular, fontSize: 9)),
                  ]),
              ],
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }
}
