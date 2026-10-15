import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../l10n/gen/app_localizations.dart';
import 'pdf_report_renderer.dart';
import 'report_dataset.dart';
import 'report_output.dart';

/// Opens the report as it will print: every page of the real PDF, with
/// zoom, and print / share from the same screen.
Future<void> showReportPdfPreview(BuildContext context, ReportDataset data, ReportLetterhead head) =>
    showPdfPreview(context, title: data.title, fileName: data.fileName, build: () => ReportOutput.pdf(data, head));

/// The same full-screen preview for any PDF (mark sheets, cards...).
Future<void> showPdfPreview(
  BuildContext context, {
  required String title,
  required String fileName,
  required Future<Uint8List> Function() build,
}) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _PdfPreviewPage(title: title, fileName: fileName, makePdf: build),
  ));
}

class _PdfPreviewPage extends StatelessWidget {
  const _PdfPreviewPage({required this.title, required this.fileName, required this.makePdf});

  final String title;
  final String fileName;
  final Future<Uint8List> Function() makePdf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isEmpty ? l10n.reportPreview : title),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PdfPreview(
        build: (_) => makePdf(),
        pdfFileName: '$fileName.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
