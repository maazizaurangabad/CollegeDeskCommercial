import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../platform/reporting/pdf_report_renderer.dart';
import '../domain/certificate_models.dart';

/// Draws certificates. Bonafide and Character fit on half an A4 sheet
/// (with an optional office copy on the other half); the leaving
/// certificate, NOC and No Dues use a full A4 page.
abstract final class CertificatePdf {
  static Future<Uint8List> build({
    required CertificateKind kind,
    required Map<String, String> f,
    required String serialLabel,
    required DateTime issuedOn,
    required ReportLetterhead head,
    required ReportFonts fonts,
    required String institutionWord,
    bool duplicate = false,
    bool officeCopy = true,
  }) async {
    final regular = pw.Font.ttf(fonts.regular);
    final bold = pw.Font.ttf(fonts.bold);
    final brand = PdfColor.fromInt(head.brandColor);
    final logo = head.logo == null ? null : pw.MemoryImage(head.logo!);
    final doc = pw.Document(title: '$serialLabel ${f[CertField.name] ?? ''}', author: head.name, creator: 'Shiksha Desk');
    final date = DateFormat('dd/MM/yyyy').format(issuedOn);
    final g = _Pronouns(f[CertField.gender] ?? '');
    pw.TextStyle st({double size = 11, bool b = false, PdfColor? color}) =>
        pw.TextStyle(font: b ? bold : regular, fontSize: size, color: color, lineSpacing: 3);

    pw.Widget letterhead() => pw.Column(children: [
          pw.Row(children: [
            if (logo != null) pw.SizedBox(width: 52, height: 52, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            pw.Expanded(
              child: pw.Column(children: [
                pw.Text(head.name, textAlign: pw.TextAlign.center, style: st(size: 16, b: true, color: brand)),
                for (final l in head.lines.where((l) => l.trim().isNotEmpty))
                  pw.Text(l, textAlign: pw.TextAlign.center, style: st(size: 8.5, color: PdfColors.grey700)),
              ]),
            ),
            if (logo != null) pw.SizedBox(width: 52),
          ]),
          pw.SizedBox(height: 6),
          pw.Container(height: 1.5, color: brand),
          pw.SizedBox(height: 1.5),
          pw.Container(height: 0.5, color: brand),
        ]);

    pw.Widget titleBlock(String title, {String? sub}) => pw.Column(children: [
          pw.SizedBox(height: 10),
          pw.Text(title,
              style: pw.TextStyle(font: bold, fontSize: 15, letterSpacing: 1.2, decoration: pw.TextDecoration.underline)),
          if (sub != null) pw.Text(sub, style: st(size: 10)),
          pw.SizedBox(height: 8),
        ]);

    pw.Widget meta({bool gr = true}) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: 'No.: ', style: st(size: 10)),
            pw.TextSpan(text: serialLabel, style: st(size: 10, b: true)),
            if (gr && (f[CertField.grNumber] ?? '').isNotEmpty) ...[
              pw.TextSpan(text: '      GR No.: ', style: st(size: 10)),
              pw.TextSpan(text: f[CertField.grNumber], style: st(size: 10, b: true)),
            ],
          ])),
          pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: 'Date: ', style: st(size: 10)),
            pw.TextSpan(text: date, style: st(size: 10, b: true)),
          ])),
        ]);

    pw.Widget duplicateMark() => duplicate
        ? pw.Align(
            alignment: pw.Alignment.topRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red800, width: 1.2)),
              child: pw.Text('DUPLICATE', style: st(size: 10, b: true, color: PdfColors.red800)),
            ),
          )
        : pw.SizedBox();

    /// A paragraph where {{value}} parts are bold.
    pw.Widget para(String text, {double size = 11.5}) {
      final spans = <pw.TextSpan>[];
      final re = RegExp(r'\{\{(.*?)\}\}');
      var last = 0;
      for (final m in re.allMatches(text)) {
        if (m.start > last) spans.add(pw.TextSpan(text: text.substring(last, m.start), style: st(size: size)));
        final v = m.group(1)!.trim();
        spans.add(pw.TextSpan(text: v.isEmpty ? '______________' : v, style: st(size: size, b: true)));
        last = m.end;
      }
      if (last < text.length) spans.add(pw.TextSpan(text: text.substring(last), style: st(size: size)));
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.RichText(textAlign: pw.TextAlign.justify, text: pw.TextSpan(children: spans)),
      );
    }

    pw.Widget signatures(List<String> who) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 28),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            for (final w in who)
              pw.Column(children: [
                pw.Container(width: 120, height: 0.7, color: PdfColors.grey700),
                pw.SizedBox(height: 3),
                pw.Text(w, style: st(size: 10)),
              ]),
          ]),
        );

    String v(String key) => '{{${f[key] ?? ''}}}';
    final name = '${g.title} ${v(CertField.name)}'.trim();
    final purpose = (f[CertField.purpose] ?? '').trim();
    final remarks = (f[CertField.remarks] ?? '').trim();

    pw.Widget halfBody(String copyLabel) {
      final title = kind == CertificateKind.bonafide ? 'BONAFIDE CERTIFICATE' : 'CHARACTER CERTIFICATE';
      final paragraphs = kind == CertificateKind.bonafide
          ? [
              'This is to certify that $name is a bonafide student of this $institutionWord, studying in '
                  '${v(CertField.className)} during the academic year ${v(CertField.academicYear)}.',
              '${g.his} date of birth as per our General Register is ${v(CertField.dateOfBirth)} '
                  '(${v(CertField.dateOfBirthWords)}).',
              if (purpose.isNotEmpty) 'This certificate is issued on ${g.his.toLowerCase()} request for {{$purpose}}.',
              if (remarks.isNotEmpty) remarks,
            ]
          : [
              'This is to certify that $name has been a student of this $institutionWord, ${v(CertField.studyingSince)}.',
              'To the best of our knowledge, ${g.his.toLowerCase()} conduct and character during this period were '
                  '${v(CertField.conduct)}.',
              if (remarks.isNotEmpty) remarks,
              'We wish ${g.him} every success in life.',
            ];
      return pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: brand, width: 1)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Stack(children: [
            letterhead(),
            if (copyLabel.isNotEmpty)
              pw.Positioned(right: 0, top: 0, child: pw.Text(copyLabel, style: st(size: 8, color: PdfColors.grey600))),
          ]),
          pw.Center(child: titleBlock(title)),
          meta(),
          pw.SizedBox(height: 10),
          for (final p in paragraphs) para(p, size: 11),
          signatures(['Clerk', 'Principal']),
        ]),
      );
    }

    if (kind == CertificateKind.bonafide || kind == CertificateKind.character) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 24, 30, 24),
        build: (context) => pw.Column(children: [
          pw.SizedBox(height: 382, child: halfBody(officeCopy ? 'Student copy' : '')),
          pw.SizedBox(height: 12),
          if (officeCopy) ...[
            pw.Row(children: [
              for (var i = 0; i < 60; i++)
                pw.Expanded(child: pw.Container(height: 0.6, color: i.isEven ? PdfColors.grey500 : PdfColors.white)),
            ]),
            pw.Text('cut here', style: st(size: 7, color: PdfColors.grey500)),
            pw.SizedBox(height: 4),
            pw.SizedBox(height: 382, child: halfBody('Office copy')),
          ],
        ]),
      ));
      return doc.save();
    }

    pw.Widget fullPage(List<pw.Widget> children) => pw.Container(
          padding: const pw.EdgeInsets.all(18),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: brand, width: 2)),
          child: pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: brand, width: 0.6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: children),
          ),
        );

    switch (kind) {
      case CertificateKind.leaving:
        final items = <(String, String)>[
          ('Full name of the student', f[CertField.name] ?? ''),
          ("Mother's name", f[CertField.motherName] ?? ''),
          ('Nationality', f[CertField.nationality] ?? ''),
          ('Mother tongue', f[CertField.motherTongue] ?? ''),
          ('Religion', f[CertField.religion] ?? ''),
          ('Caste and sub-caste', f[CertField.casteSubcaste] ?? ''),
          ('Place of birth', f[CertField.placeOfBirth] ?? ''),
          ('Date of birth (in figures)', f[CertField.dateOfBirth] ?? ''),
          ('Date of birth (in words)', f[CertField.dateOfBirthWords] ?? ''),
          ('Last school / college attended', f[CertField.previousSchool] ?? ''),
          ('Date of admission and class', f[CertField.admissionDateClass] ?? ''),
          ('Progress', f[CertField.progress] ?? ''),
          ('Conduct', f[CertField.conduct] ?? ''),
          ('Date of leaving', f[CertField.leavingDate] ?? ''),
          ('Class in which studying and since when', f[CertField.studyingSince] ?? ''),
          ('Reason for leaving', f[CertField.leavingReason] ?? ''),
          ('Remarks', f[CertField.remarks] ?? ''),
        ];
        final ids = [
          if ((f[CertField.saralId] ?? '').isNotEmpty) 'Student ID: ${f[CertField.saralId]}',
          if ((f[CertField.pen] ?? '').isNotEmpty) 'PEN: ${f[CertField.pen]}',
          if ((f[CertField.apaar] ?? '').isNotEmpty) 'APAAR: ${f[CertField.apaar]}',
        ];
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(22),
          build: (context) => fullPage([
            duplicateMark(),
            letterhead(),
            pw.Center(child: titleBlock('LEAVING CERTIFICATE', sub: '(Nirgam Utara)')),
            meta(),
            if (ids.isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.Text(ids.join('      '), style: st(size: 9.5)),
            ],
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
              columnWidths: const {0: pw.FixedColumnWidth(24), 1: pw.FixedColumnWidth(190), 2: pw.FlexColumnWidth()},
              children: [
                for (var i = 0; i < items.length; i++)
                  pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${i + 1}', style: st(size: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(items[i].$1, style: st(size: 10))),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(items[i].$2.isEmpty ? '' : items[i].$2, style: st(size: 10.5, b: true)),
                    ),
                  ]),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Text('Certified that the above information is in accordance with the General Register of this $institutionWord.',
                style: st(size: 10)),
            pw.Spacer(),
            signatures(['Class Teacher', 'Clerk', 'Principal']),
          ]),
        ));
      case CertificateKind.noDues:
        const sections = ['Library', 'Laboratory', 'Office / Accounts', 'Sports', 'Class Teacher'];
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(22),
          build: (context) => fullPage([
            letterhead(),
            pw.Center(child: titleBlock('NO DUES CERTIFICATE')),
            meta(),
            pw.SizedBox(height: 12),
            para('This is to certify that $name of ${v(CertField.className)} (academic year ${v(CertField.academicYear)}) '
                'has no dues pending with the following sections of this $institutionWord.'),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
              columnWidths: const {0: pw.FixedColumnWidth(28), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(1.5)},
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: brand),
                  children: [
                    for (final h in ['No.', 'Section', 'Remarks', 'Signature'])
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(h, style: st(size: 10, b: true, color: PdfColors.white))),
                  ],
                ),
                for (var i = 0; i < sections.length; i++)
                  pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(10), child: pw.Text('${i + 1}', style: st(size: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(10), child: pw.Text(sections[i], style: st(size: 10.5))),
                    pw.SizedBox(height: 30),
                    pw.SizedBox(height: 30),
                  ]),
              ],
            ),
            pw.SizedBox(height: 12),
            if (purpose.isNotEmpty) para('This certificate is issued for {{$purpose}}.'),
            if (remarks.isNotEmpty) para(remarks),
            pw.Spacer(),
            signatures(['Clerk', 'Principal']),
          ]),
        ));
      case CertificateKind.noc:
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(22),
          build: (context) => fullPage([
            letterhead(),
            pw.Center(child: titleBlock('NO OBJECTION CERTIFICATE')),
            meta(),
            pw.SizedBox(height: 16),
            para('This is to certify that $name is a bonafide student of this $institutionWord, studying in '
                '${v(CertField.className)} during the academic year ${v(CertField.academicYear)}.'),
            para('The $institutionWord has no objection to ${g.his.toLowerCase()} {{${purpose.isEmpty ? '' : purpose}}}.'),
            if (remarks.isNotEmpty) para(remarks),
            para('This certificate is issued on ${g.his.toLowerCase()} request.'),
            pw.Spacer(),
            signatures(['Clerk', 'Principal']),
          ]),
        ));
      case CertificateKind.bonafide:
      case CertificateKind.character:
        break;
    }
    return doc.save();
  }
}

class _Pronouns {
  _Pronouns(String gender)
      : title = gender == 'Male' ? 'Kumar' : (gender == 'Female' ? 'Kumari' : ''),
        his = gender == 'Male' ? 'His' : (gender == 'Female' ? 'Her' : 'Their'),
        him = gender == 'Male' ? 'him' : (gender == 'Female' ? 'her' : 'them');

  final String title;
  final String his;
  final String him;
}
