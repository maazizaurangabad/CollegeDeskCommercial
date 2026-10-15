import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../l10n/gen/app_localizations.dart';
import 'pdf_report_renderer.dart';
import 'report_dataset.dart';
import 'report_output.dart';

/// Opens the report as it will print: every page of the real PDF, with
/// zoom, and print / share from the same screen.
Future<void> showReportPdfPreview(BuildContext context, ReportDataset data, ReportLetterhead head) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _ReportPdfPreviewPage(data: data, head: head),
  ));
}

class _ReportPdfPreviewPage extends StatelessWidget {
  const _ReportPdfPreviewPage({required this.data, required this.head});

  final ReportDataset data;
  final ReportLetterhead head;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(data.title.isEmpty ? l10n.reportPreview : data.title),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PdfPreview(
        build: (_) => ReportOutput.pdf(data, head),
        pdfFileName: '${data.fileName}.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
