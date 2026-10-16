import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../platform/reporting/pdf_report_renderer.dart';

/// One document for the PDF: its name, a line of details and its pages
/// (pictures). PDF files are turned into pictures first by the caller.
typedef PdfDocumentPart = ({String label, String details, List<Uint8List> pages});

/// A student's documents as one PDF: a first page listing what is inside,
/// then every page of every document, each with its name on top. With one
/// document, there is no first page.
Future<Uint8List> buildDocumentsPdf({
  required String title,
  required List<String> about,
  required List<PdfDocumentPart> parts,
  required ReportFonts fonts,
  required String generatedLine,
}) async {
  final theme = pw.ThemeData.withFont(base: pw.Font.ttf(fonts.regular), bold: pw.Font.ttf(fonts.bold));
  final doc = pw.Document(theme: theme, title: title);
  const grey = PdfColor.fromInt(0xFF5B6470);

  if (parts.length > 1) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final line in about) pw.Text(line, style: const pw.TextStyle(fontSize: 10.5, color: grey)),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Document', 'Details', 'Pages'],
            data: [
              for (var i = 0; i < parts.length; i++)
                ['${i + 1}', parts[i].label, parts[i].details, '${parts[i].pages.length}'],
            ],
            headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(4),
              3: const pw.FixedColumnWidth(40),
            },
          ),
          pw.Spacer(),
          pw.Text(generatedLine, style: const pw.TextStyle(fontSize: 8.5, color: grey)),
        ],
      ),
    ));
  }

  for (final part in parts) {
    for (var i = 0; i < part.pages.length; i++) {
      final image = pw.MemoryImage(part.pages[i]);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(children: [
              pw.Expanded(child: pw.Text(part.label, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
              pw.Text('${about.isEmpty ? '' : '${about.first} · '}${i + 1} / ${part.pages.length}',
                  style: const pw.TextStyle(fontSize: 9, color: grey)),
            ]),
            pw.SizedBox(height: 6),
            pw.Expanded(child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))),
          ],
        ),
      ));
    }
  }
  return doc.save();
}
