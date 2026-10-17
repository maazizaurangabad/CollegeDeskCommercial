import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../platform/reporting/pdf_report_renderer.dart';
import '../domain/fee_models.dart';

/// A fee receipt on half an A4 sheet: student copy on top, office copy
/// below a cut line. Amounts are written as "Rs." so every font can print them.
abstract final class FeeReceiptPdf {
  static Future<Uint8List> build({
    required FeeReceiptRecord r,
    required ReportLetterhead head,
    required ReportFonts fonts,
    required String modeLabel,
    bool officeCopy = true,
    String? issuedBy,
  }) async {
    final regular = pw.Font.ttf(fonts.regular);
    final bold = pw.Font.ttf(fonts.bold);
    final brand = PdfColor.fromInt(head.brandColor);
    final logo = head.logo == null ? null : pw.MemoryImage(head.logo!);
    final doc = pw.Document(title: '${r.serialLabel} ${r.studentName}', author: head.name, creator: 'Shiksha Desk');
    pw.TextStyle st({double size = 10, bool b = false, PdfColor? color}) =>
        pw.TextStyle(font: b ? bold : regular, fontSize: size, color: color);
    String rs(int v) => 'Rs. ${Rupees.format(v)}';

    pw.Widget cell(String text, {bool b = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(text, style: st(size: 9.5, b: b), textAlign: align),
        );

    pw.Widget body(String copy) {
      final info = <(String, String)>[
        ('Name', r.studentName),
        ('Class', r.classLabel),
        if ((r.grNumber ?? '').isNotEmpty) ('GR No.', r.grNumber!),
        ('Academic year', r.academicYearLabel),
      ];
      return pw.Stack(children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Row(children: [
            if (logo != null) pw.SizedBox(width: 40, height: 40, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            pw.Expanded(
              child: pw.Column(children: [
                pw.Text(head.name, textAlign: pw.TextAlign.center, style: st(size: 13, b: true, color: brand)),
                for (final l in head.lines.where((l) => l.trim().isNotEmpty))
                  pw.Text(l, textAlign: pw.TextAlign.center, style: st(size: 7.5, color: PdfColors.grey700)),
              ]),
            ),
            if (logo != null) pw.SizedBox(width: 40),
          ]),
          pw.SizedBox(height: 4),
          pw.Container(height: 1.2, color: brand),
          pw.SizedBox(height: 6),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('No.: ${r.serialLabel}', style: st(b: true)),
            pw.Text('FEE RECEIPT', style: st(size: 12, b: true)),
            pw.Text('Date: ${DateFormat('dd/MM/yyyy').format(r.receivedOn)}', style: st(b: true)),
          ]),
          if (copy.isNotEmpty)
            pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(copy, style: st(size: 7.5, color: PdfColors.grey600))),
          pw.SizedBox(height: 4),
          pw.Wrap(spacing: 18, runSpacing: 2, children: [
            for (final (k, v) in info)
              pw.RichText(text: pw.TextSpan(children: [
                pw.TextSpan(text: '$k: ', style: st()),
                pw.TextSpan(text: v, style: st(b: true)),
              ])),
          ]),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
            columnWidths: const {0: pw.FixedColumnWidth(28), 1: pw.FlexColumnWidth(), 2: pw.FixedColumnWidth(90)},
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
                cell('Sr.', b: true, align: pw.TextAlign.center),
                cell('Particulars', b: true),
                cell('Amount', b: true, align: pw.TextAlign.right),
              ]),
              for (var i = 0; i < r.lines.length; i++)
                pw.TableRow(children: [
                  cell('${i + 1}', align: pw.TextAlign.center),
                  cell(r.lines[i].headName),
                  cell(rs(r.lines[i].amount), align: pw.TextAlign.right),
                ]),
              pw.TableRow(children: [
                cell(''),
                cell('Total', b: true),
                cell(rs(r.total), b: true, align: pw.TextAlign.right),
              ]),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(Rupees.words(r.total), style: st(size: 9.5, b: true)),
          pw.SizedBox(height: 3),
          pw.Text(
            [
              'Paid by: $modeLabel',
              if ((r.reference ?? '').isNotEmpty) 'Ref.: ${r.reference}',
              if (r.balanceAfter != null) 'Balance after this payment: ${rs(r.balanceAfter! < 0 ? 0 : r.balanceAfter!)}',
            ].join('     '),
            style: st(size: 9),
          ),
          if ((r.note ?? '').isNotEmpty) pw.Text('Note: ${r.note}', style: st(size: 9)),
          pw.Spacer(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Computer generated receipt', style: st(size: 7, color: PdfColors.grey600)),
            pw.Column(children: [
              if ((issuedBy ?? '').isEmpty)
                pw.SizedBox(height: 18)
              else ...[
                pw.SizedBox(height: 6),
                pw.Text(issuedBy!, style: st(size: 9, b: true)),
              ],
              pw.Text('Received by (Cashier / Clerk)', style: st(size: 9)),
            ]),
          ]),
        ]),
        if (r.isCancelled)
          pw.Center(
            child: pw.Transform.rotateBox(
              angle: 0.4,
              child: pw.Text('CANCELLED', style: st(size: 48, b: true, color: PdfColor.fromInt(0x55C62828))),
            ),
          ),
      ]);
    }

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(30, 24, 30, 24),
      build: (context) => pw.Column(children: [
        pw.SizedBox(height: 382, child: body(officeCopy ? 'Student copy' : '')),
        pw.SizedBox(height: 12),
        if (officeCopy) ...[
          pw.Row(children: [
            for (var i = 0; i < 60; i++)
              pw.Expanded(child: pw.Container(height: 0.6, color: i.isEven ? PdfColors.grey500 : PdfColors.white)),
          ]),
          pw.Text('cut here', style: st(size: 7, color: PdfColors.grey500)),
          pw.SizedBox(height: 4),
          pw.SizedBox(height: 382, child: body('Office copy')),
        ],
      ]),
    ));
    return doc.save();
  }
}
