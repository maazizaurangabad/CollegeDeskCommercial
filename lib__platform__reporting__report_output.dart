import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../core/files/csv.dart';
import '../../core/files/save_file.dart';
import '../../core/files/xlsx_styled.dart';
import 'pdf_report_renderer.dart';
import 'report_dataset.dart';

/// Turns a dataset into files and hands them to the system: save, share, print.
abstract final class ReportOutput {
  static ReportFonts? _fonts;

  static Future<ReportFonts> fonts() async => _fonts ??= ReportFonts(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
      );

  static Future<Uint8List> pdf(ReportDataset data, ReportLetterhead head) async =>
      PdfReportRenderer.render(data, head, await fonts());

  /// Saves the PDF where the user chooses (Downloads, Google Drive...).
  static Future<bool> savePdf(ReportDataset data, ReportLetterhead head, {required String title}) async =>
      saveBytesWithDialog(fileName: '${data.fileName}.pdf', bytes: await pdf(data, head), title: title);

  /// Opens the share sheet (WhatsApp, email, Drive). On Windows, saves instead.
  static Future<void> sharePdf(ReportDataset data, ReportLetterhead head, {required String title}) async {
    final bytes = await pdf(data, head);
    if (Platform.isAndroid || Platform.isIOS) {
      await Printing.sharePdf(bytes: bytes, filename: '${data.fileName}.pdf');
    } else {
      await saveBytesWithDialog(fileName: '${data.fileName}.pdf', bytes: bytes, title: title);
    }
  }

  static Future<void> printPdf(ReportDataset data, ReportLetterhead head) async {
    final bytes = await pdf(data, head);
    await Printing.layoutPdf(name: data.fileName, onLayout: (_) async => bytes);
  }

  /// A formatted Excel file: headings, coloured frozen header with filter
  /// buttons, sized columns, shading, real numbers and dates, print settings.
  static List<int> excelBytes(ReportDataset data, ReportLetterhead head) {
    final table = data.tableForExport();
    return XlsxStyledWriter.write(
      sheetName: data.title,
      headingLines: [head.name, data.title, ...data.subtitle.where((s) => s.trim().isNotEmpty)],
      header: table.header,
      rows: table.rows,
      types: [
        for (final t in data.exportTypes())
          switch (t) {
            ReportColumnType.number => XlsxCellType.number,
            ReportColumnType.date => XlsxCellType.date,
            ReportColumnType.text => XlsxCellType.text,
          },
      ],
      notes: data.notes,
      landscape: data.landscape || table.header.length > 7,
      brandColor: head.brandColor,
    );
  }

  static Future<bool> saveExcel(ReportDataset data, ReportLetterhead head, {required String title}) =>
      saveBytesWithDialog(fileName: '${data.fileName}.xlsx', bytes: excelBytes(data, head), title: title);

  static Future<bool> saveCsv(ReportDataset data, {required String title}) {
    final table = data.tableForExport();
    return saveBytesWithDialog(
      fileName: '${data.fileName}.csv',
      bytes: CsvReader.write(table.header, table.rows),
      title: title,
    );
  }
}
