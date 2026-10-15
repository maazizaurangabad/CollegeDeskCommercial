import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/files/save_file.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/certificates_providers.dart';
import '../domain/certificate_models.dart';

/// Opens a certificate over the current screen (the register keeps its
/// search and filters underneath). Viewing changes nothing in the register.
Future<void> openCertificateView(BuildContext context, String id) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(body: SafeArea(child: CertificateViewScreen(id: id, overlay: true))),
  ));
}

/// An issued certificate: the real document as it prints, with Print,
/// Save PDF and Cancel. Viewing does not issue, number or change anything;
/// printing and saving are counted in the register.
class CertificateViewScreen extends ConsumerStatefulWidget {
  const CertificateViewScreen({super.key, required this.id, this.overlay = false});

  final String id;

  /// Opened over the register (close returns to it as it was).
  final bool overlay;

  @override
  ConsumerState<CertificateViewScreen> createState() => _CertificateViewScreenState();
}

class _CertificateViewScreenState extends ConsumerState<CertificateViewScreen> {
  late Future<CertificateRecord?> _record = ref.read(certificateRepositoryProvider).get(widget.id);

  Future<void> _cancel(CertificateRecord r) async {
    final l10n = AppLocalizations.of(context);
    final reason = await SdDialog.prompt(
      context,
      title: l10n.certCancel,
      label: l10n.certCancelReason,
      confirmLabel: l10n.certCancel,
      cancelLabel: l10n.cancel,
    );
    if (reason == null || reason.trim().isEmpty) return;
    await ref.read(certificateRepositoryProvider).cancel(r.id, reason);
    ref.read(certificatesRevisionProvider.notifier).state++;
    setState(() => _record = ref.read(certificateRepositoryProvider).get(widget.id));
  }

  Future<Uint8List> _pdf(CertificateRecord r) => certificatePdf(
        ref,
        kind: r.kind,
        fields: r.fields,
        serialLabel: r.serialLabel,
        issuedOn: r.issuedOn,
        duplicate: r.isDuplicate,
        officeCopy: r.fields['office_copy'] != 'false',
        cancelled: r.status == CertificateStatus.cancelled,
      );

  Future<void> _print(CertificateRecord r) async {
    final bytes = await _pdf(r);
    final done = await Printing.layoutPdf(name: r.serialLabel, onLayout: (_) async => bytes);
    if (done && r.status != CertificateStatus.cancelled) _printed();
  }

  Future<void> _save(CertificateRecord r) async {
    final l10n = AppLocalizations.of(context);
    try {
      final saved = await saveBytesWithDialog(
        fileName: '${r.serialLabel.replaceAll('/', '-')}.pdf',
        bytes: await _pdf(r),
        title: l10n.reportSavePdf,
      );
      if (!saved) return;
      if (r.status != CertificateStatus.cancelled) _printed();
      if (mounted) SdToast.show(context, l10n.exported);
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    }
  }

  void _close() {
    if (widget.overlay && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/certificates');
    }
  }

  void _printed() {
    ref.read(certificateRepositoryProvider).recordPrint(widget.id).then((_) {
      ref.read(certificatesRevisionProvider.notifier).state++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<CertificateRecord?>(
      future: _record,
      builder: (context, snapshot) {
        final r = snapshot.data;
        if (r == null) {
          return snapshot.connectionState == ConnectionState.done
              ? SdEmptyState(icon: Icons.search_off, title: l10n.issueNotFound, message: '')
              : const Center(child: CircularProgressIndicator());
        }
        final cancelled = r.status == CertificateStatus.cancelled;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SdSpace.lg, SdSpace.lg, SdSpace.lg, SdSpace.sm),
            child: Row(children: [
              IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: _close),
              const SizedBox(width: SdSpace.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(certificateTitle(l10n, r.kind), style: theme.textTheme.titleMedium),
                  Text(
                    [
                      r.studentName,
                      r.serialLabel,
                      if (r.printCount > 0) l10n.certPrintCount(r.printCount),
                      if (cancelled) '${l10n.certCancelled}: ${r.cancelReason ?? ''}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ]),
              ),
              IconButton(tooltip: l10n.resPrint, icon: const Icon(Icons.print_outlined), onPressed: () => _print(r)),
              IconButton(tooltip: l10n.reportSavePdf, icon: const Icon(Icons.download_outlined), onPressed: () => _save(r)),
              if (!cancelled)
                SdButton(label: l10n.certCancel, variant: SdButtonVariant.text, onPressed: () => _cancel(r)),
            ]),
          ),
          Expanded(
            child: PdfPreview(
                    build: (_) => _pdf(r),
                    pdfFileName: '${r.serialLabel.replaceAll('/', '-')}.pdf',
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    onPrinted: (_) {
                      if (!cancelled) _printed();
                    },
                    onShared: (_) {
                      if (!cancelled) _printed();
                    },
                  ),
          ),
        ]);
      },
    );
  }
}
