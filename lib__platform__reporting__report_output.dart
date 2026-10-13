import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../core/files/csv.dart';
import '../../core/files/save_file.dart';
import '../../core/files/xlsx.dart';
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

  static Future<bool> saveExcel(ReportDataset data, {required String title}) => saveBytesWithDialog(
        fileName: '${data.fileName}.xlsx',
        bytes: XlsxWriter.write(
          sheetName: data.title,
          header: [for (final c in data.columns) c.label],
          rows: [
            for (final s in data.subtitle) [s],
            ...data.tableForExport(),
          ],
        ),
        title: title,
      );

  static Future<bool> saveCsv(ReportDataset data, {required String title}) => saveBytesWithDialog(
        fileName: '${data.fileName}.csv',
        bytes: CsvReader.write([for (final c in data.columns) c.label], data.tableForExport()),
        title: title,
      );
}
