import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/certificates_providers.dart';
import '../domain/certificate_models.dart';

/// An issued certificate: preview, print, share, or cancel.
/// Printing and sharing are counted in the register.
class CertificateViewScreen extends ConsumerStatefulWidget {
  const CertificateViewScreen({super.key, required this.id});

  final String id;

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
              IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/certificates')),
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
              if (!cancelled)
                SdButton(label: l10n.certCancel, variant: SdButtonVariant.text, onPressed: () => _cancel(r)),
            ]),
          ),
          Expanded(
            child: cancelled
                ? SdEmptyState(icon: Icons.block, title: l10n.certCancelled, message: r.cancelReason ?? '')
                : PdfPreview(
                    build: (_) => certificatePdf(
                      ref,
                      kind: r.kind,
                      fields: r.fields,
                      serialLabel: r.serialLabel,
                      issuedOn: r.issuedOn,
                      duplicate: r.isDuplicate,
                      officeCopy: r.fields['office_copy'] != 'false',
                    ),
                    pdfFileName: '${r.serialLabel.replaceAll('/', '-')}.pdf',
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    onPrinted: (_) => _printed(),
                    onShared: (_) => _printed(),
                  ),
          ),
        ]);
      },
    );
  }
}
