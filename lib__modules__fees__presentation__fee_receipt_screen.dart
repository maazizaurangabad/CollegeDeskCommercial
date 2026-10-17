import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../platform/organization/organization_providers.dart';
import '../../../platform/staff/staff_models.dart';
import '../../../platform/staff/staff_providers.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/fees_providers.dart';
import '../domain/fee_models.dart';

/// One receipt: preview, print, share or save, or cancel it.
class FeeReceiptScreen extends ConsumerStatefulWidget {
  const FeeReceiptScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<FeeReceiptScreen> createState() => _FeeReceiptScreenState();
}

class _FeeReceiptScreenState extends ConsumerState<FeeReceiptScreen> {
  late Future<FeeReceiptRecord?> _record = ref.read(feeRepositoryProvider).receipt(widget.id);

  Future<void> _cancel(FeeReceiptRecord r) async {
    final l10n = AppLocalizations.of(context);
    final reason = await SdDialog.prompt(
      context,
      title: l10n.feeCancelReceipt,
      label: l10n.feeCancelReason,
      confirmLabel: l10n.feeCancelReceipt,
      cancelLabel: l10n.cancel,
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    try {
      await ref.read(feeRepositoryProvider).cancelReceipt(r.id, reason);
      if (!mounted) return;
      ref.read(feesRevisionProvider.notifier).state++;
      setState(() => _record = ref.read(feeRepositoryProvider).receipt(widget.id));
    } catch (e) {
      if (mounted) SdToast.show(context, feeErrorMessage(l10n, e));
    }
  }

  void _printed() {
    ref.read(feeRepositoryProvider).recordPrint(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<FeeReceiptRecord?>(
      future: _record,
      builder: (context, snapshot) {
        final r = snapshot.data;
        if (r == null) {
          return snapshot.connectionState == ConnectionState.done
              ? SdEmptyState(icon: Icons.search_off, title: l10n.issueNotFound, message: '')
              : const Center(child: CircularProgressIndicator());
        }
        final names = ref.watch(staffNamesProvider).valueOrNull ?? const <String, String>{};
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SdSpace.lg, SdSpace.lg, SdSpace.lg, SdSpace.sm),
            child: Row(children: [
              IconButton(
                tooltip: l10n.back,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/fees/student/${r.studentId}'),
              ),
              const SizedBox(width: SdSpace.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.serialLabel} · ${rupees(r.total)}', style: theme.textTheme.titleMedium),
                  Text(
                    [
                      r.studentName,
                      paymentModeLabel(l10n, r.mode),
                      if (userDisplayName(names, r.createdBy, adminName: l10n.staffAdminName) case final by?)
                        l10n.staffIssuedBy(by),
                      if (r.isCancelled) '${l10n.certCancelled}: ${r.cancelReason ?? ''}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ]),
              ),
              if (!r.isCancelled && ref.watch(permissionCheckerProvider)(Permissions.feesCancel))
                SdButton(label: l10n.feeCancelReceipt, variant: SdButtonVariant.text, onPressed: () => _cancel(r)),
            ]),
          ),
          Expanded(
            child: PdfPreview(
              build: (_) => feeReceiptPdf(ref, l10n, r),
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
