import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../platform/reporting/pdf_report_renderer.dart';
import '../domain/result_models.dart';

/// Words printed on the mark sheet (from the app's language file).
class MarkSheetWords {
  const MarkSheetWords({
    required this.title,
    required this.name,
    required this.gr,
    required this.roll,
    required this.className,
    required this.year,
    required this.subject,
    required this.max,
    required this.pass,
    required this.obtained,
    required this.remark,
    required this.total,
    required this.percentage,
    required this.resultClass,
    required this.rank,
    required this.result,
    required this.gradeSubjects,
    required this.classTeacher,
    required this.principal,
    required this.parent,
    required this.statusLabel,
    required this.classLabel,
  });

  final String title, name, gr, roll, className, year, subject, max, pass, obtained, remark;
  final String total, percentage, resultClass, rank, result, gradeSubjects, classTeacher, principal, parent;
  final String Function(ResultStatus) statusLabel;
  final String Function(ResultClass) classLabel;
}

/// One A4 page per student: subject-wise marks, total, %, class, rank and
/// result, with signature lines.
abstract final class MarkSheetPdf {
  static Future<Uint8List> build({
    required List<StudentResult> results,
    required List<SubjectColumn> columns,
    required String examName,
    required String classLabel,
    required String yearLabel,
    required ResultRules rules,
    required ReportLetterhead head,
    required ReportFonts fonts,
    required MarkSheetWords words,
  }) async {
    final regular = pw.Font.ttf(fonts.regular);
    final bold = pw.Font.ttf(fonts.bold);
    final brand = PdfColor.fromInt(head.brandColor);
    final logo = head.logo == null ? null : pw.MemoryImage(head.logo!);
    final doc = pw.Document(title: '$examName $classLabel', author: head.name, creator: 'Shiksha Desk');
    pw.TextStyle st({double size = 10.5, bool b = false, PdfColor? color}) =>
        pw.TextStyle(font: b ? bold : regular, fontSize: size, color: color);
    pw.Widget cell(String t, {bool b = false, pw.TextAlign align = pw.TextAlign.center, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(t, style: st(b: b, color: color), textAlign: align),
        );
    final marksCols = columns.where((c) => !c.isGrade).toList();
    final gradeCols = columns.where((c) => c.isGrade).toList();

    for (final r in results) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
        build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Row(children: [
            if (logo != null) pw.SizedBox(width: 54, height: 54, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            pw.Expanded(
              child: pw.Column(children: [
                pw.Text(head.name, textAlign: pw.TextAlign.center, style: st(size: 16, b: true, color: brand)),
                for (final l in head.lines.where((l) => l.trim().isNotEmpty))
                  pw.Text(l, textAlign: pw.TextAlign.center, style: st(size: 8.5, color: PdfColors.grey700)),
              ]),
            ),
            if (logo != null) pw.SizedBox(width: 54),
          ]),
          pw.SizedBox(height: 6),
          pw.Container(height: 1.5, color: brand),
          pw.SizedBox(height: 10),
          pw.Center(child: pw.Text(words.title.toUpperCase(), style: st(size: 14, b: true))),
          pw.Center(child: pw.Text('$examName · $yearLabel', style: st(size: 11))),
          pw.SizedBox(height: 12),
          pw.Table(
            columnWidths: const {0: pw.FlexColumnWidth(1.2), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1.4)},
            children: [
              pw.TableRow(children: [
                pw.Text('${words.name}:', style: st()),
                pw.Text(r.name, style: st(b: true)),
                pw.Text('${words.gr}:', style: st()),
                pw.Text(r.grNumber ?? '-', style: st(b: true)),
              ]),
              pw.TableRow(children: [
                pw.Text('${words.className}:', style: st()),
                pw.Text(classLabel, style: st(b: true)),
                pw.Text('${words.roll}:', style: st()),
                pw.Text(r.rollNumber?.toString() ?? '-', style: st(b: true)),
              ]),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
            columnWidths: const {
              0: pw.FixedColumnWidth(30),
              1: pw.FlexColumnWidth(3),
              2: pw.FixedColumnWidth(60),
              3: pw.FixedColumnWidth(60),
              4: pw.FixedColumnWidth(70),
              5: pw.FixedColumnWidth(70),
            },
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
                cell('Sr', b: true),
                cell(words.subject, b: true, align: pw.TextAlign.left),
                cell(words.max, b: true),
                cell(words.pass, b: true),
                cell(words.obtained, b: true),
                cell(words.remark, b: true),
              ]),
              for (var i = 0; i < marksCols.length; i++)
                () {
                  final c = r.columns[marksCols[i].name];
                  final failed = c != null && !c.missing && !c.passed;
                  return pw.TableRow(children: [
                    cell('${i + 1}'),
                    cell(c?.subject?.name ?? marksCols[i].name, align: pw.TextAlign.left),
                    cell('${c?.max ?? marksCols[i].subjects.first.maxMarks}'),
                    cell('${_passFor(c, marksCols[i])}'),
                    cell(c?.text ?? '-', b: true, color: failed ? PdfColors.red800 : null),
                    cell(c == null || c.missing ? '' : (c.passed ? 'P' : 'F'), color: failed ? PdfColors.red800 : null),
                  ]);
                }(),
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey100), children: [
                cell(''),
                cell(words.total, b: true, align: pw.TextAlign.left),
                cell('${r.maxTotal}', b: true),
                cell(''),
                cell('${r.total}', b: true),
                cell(''),
              ]),
            ],
          ),
          if (gradeCols.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(words.gradeSubjects, style: st(b: true)),
            pw.SizedBox(height: 4),
            pw.Wrap(spacing: 24, runSpacing: 4, children: [
              for (final g in gradeCols)
                pw.Text('${r.columns[g.name]?.subject?.name ?? g.name}: ${r.columns[g.name]?.text ?? '-'}', style: st()),
            ]),
          ],
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: brand, width: 1)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
              _figure(st, words.percentage, r.maxTotal == 0 ? '-' : '${rules.percentText(r.percent)}%'),
              if (r.resultClass != null) _figure(st, words.resultClass, words.classLabel(r.resultClass!)),
              if (r.rank != null) _figure(st, words.rank, '${r.rank}'),
              _figure(st, words.result, words.statusLabel(r.status).toUpperCase(),
                  color: r.status == ResultStatus.failed ? PdfColors.red800 : null),
            ]),
          ),
          pw.Spacer(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            for (final s in [words.classTeacher, words.parent, words.principal])
              pw.Column(children: [
                pw.Container(width: 120, height: 0.6, color: PdfColors.grey700),
                pw.SizedBox(height: 3),
                pw.Text(s, style: st(size: 9.5)),
              ]),
          ]),
        ]),
      ));
    }
    return doc.save();
  }

  /// Passing marks, times the number of exams added together.
  static int _passFor(ColumnResult? c, SubjectColumn col) {
    final s = c?.subject ?? col.subjects.first;
    final n = (c == null || c.max == 0 || s.maxMarks == 0) ? 1 : c.max ~/ s.maxMarks;
    return s.passMarks * n;
  }

  static pw.Widget _figure(pw.TextStyle Function({double size, bool b, PdfColor? color}) st, String label, String value,
          {PdfColor? color}) =>
      pw.Column(children: [
        pw.Text(label, style: st(size: 9)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: st(size: 13, b: true, color: color)),
      ]);
}
