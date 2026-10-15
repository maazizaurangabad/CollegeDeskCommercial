import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/modules/module_providers.dart';
import '../../../platform/reporting/report_output.dart';
import '../../reports/application/reports_providers.dart';
import '../../students/presentation/student_labels.dart';
import '../application/fees_providers.dart';
import '../domain/fee_models.dart';

enum _Period { today, month, year, all }

/// Fees home: today's collection, the receipt register, and the way in to
/// taking a payment and to fee setup.
class FeesScreen extends ConsumerStatefulWidget {
  const FeesScreen({super.key});

  @override
  ConsumerState<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends ConsumerState<FeesScreen> {
  _Period _period = _Period.today;
  String _query = '';
  bool _busy = false;

  Future<void> _export({required bool excel}) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final (from, to) = _range();
      final data = await feeReports(ref, l10n).dayBook(from: from, to: to);
      final head = await reportLetterhead(ref);
      final saved = excel
          ? await ReportOutput.saveExcel(data, head, title: l10n.exportExcel)
          : await ReportOutput.savePdf(data, head, title: l10n.reportSavePdf);
      if (saved && mounted) SdToast.show(context, l10n.exported);
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  (DateTime?, DateTime?) _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.today => (today, today),
      _Period.month => (DateTime(now.year, now.month), today),
      _Period.year => (ref.read(academicControllerProvider).activeYear?.startDate, today),
      _Period.all => (null, null),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    ref.watch(feesRevisionProvider);
    final today = ref.watch(feesTodayProvider).valueOrNull;
    final (from, to) = _range();

    return SdPage(
      children: [
        Row(children: [
          Expanded(child: Text(l10n.navFees, style: theme.textTheme.headlineSmall)),
          IconButton(
            tooltip: l10n.feeSetup,
            icon: const Icon(Icons.tune_outlined),
            onPressed: () => context.go('/fees/setup'),
          ),
          const SizedBox(width: SdSpace.xs),
          SdButton(label: l10n.feeTakePayment, icon: Icons.add, onPressed: () => context.go('/fees/pay')),
        ]),
        const SizedBox(height: SdSpace.lg),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth < 560 ? (c.maxWidth - SdSpace.md) / 2 : (c.maxWidth - SdSpace.md * 2) / 3;
          return Wrap(spacing: SdSpace.md, runSpacing: SdSpace.md, children: [
            SizedBox(width: w, child: SdStatTile(label: l10n.feeCollectedToday, value: rupees(today?.total ?? 0))),
            SizedBox(width: w, child: SdStatTile(label: l10n.feeReceiptsToday, value: '${today?.count ?? 0}')),
            if (today != null)
              for (final e in today.byMode.entries)
                SizedBox(width: w, child: SdStatTile(label: paymentModeLabel(l10n, e.key), value: rupees(e.value))),
          ]);
        }),
        const SizedBox(height: SdSpace.xl),
        Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
          for (final (p, label) in [
            (_Period.today, l10n.msgPeriodToday),
            (_Period.month, l10n.msgPeriodMonth),
            (_Period.year, l10n.certPeriodYear),
            (_Period.all, l10n.msgPeriodAll),
          ])
            ChoiceChip(label: Text(label), selected: _period == p, onSelected: (_) => setState(() => _period = p)),
        ]),
        const SizedBox(height: SdSpace.md),
        SdTextField(hint: l10n.feeSearchReceipts, prefixIcon: Icons.search, onChanged: (v) => setState(() => _query = v.trim())),
        const SizedBox(height: SdSpace.md),
        Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
          SdButton(
            label: l10n.exportExcel,
            icon: Icons.table_chart_outlined,
            variant: SdButtonVariant.secondary,
            onPressed: _busy ? null : () => _export(excel: true),
          ),
          SdButton(
            label: l10n.reportSavePdf,
            icon: Icons.picture_as_pdf_outlined,
            variant: SdButtonVariant.secondary,
            onPressed: _busy ? null : () => _export(excel: false),
          ),
          if (ref.watch(enabledModulesProvider).contains('messages'))
            SdButton(
              label: l10n.feeReminders,
              icon: Icons.forum_outlined,
              variant: SdButtonVariant.secondary,
              onPressed: () => context.go('/fees/reminders'),
            ),
          if (ref.watch(enabledModulesProvider).contains('reports'))
            SdButton(
              label: l10n.feeAllReports,
              icon: Icons.assessment_outlined,
              variant: SdButtonVariant.text,
              onPressed: () => context.go('/reports'),
            ),
        ]),
        const SizedBox(height: SdSpace.lg),
        FutureBuilder<List<FeeReceiptRecord>>(
          future: ref.read(feeRepositoryProvider).receipts(from: from, to: to, query: _query),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text(l10n.saveFailed);
            if (!snapshot.hasData) return const SdSkeleton(height: 200);
            final items = snapshot.data!;
            if (items.isEmpty) {
              return SdEmptyState(
                icon: Icons.receipt_long_outlined,
                title: l10n.feeNoReceipts,
                message: l10n.feeNoReceiptsHint,
                action: SdButton(label: l10n.feeTakePayment, onPressed: () => context.go('/fees/pay')),
              );
            }
            final total = items.where((r) => !r.isCancelled).fold(0, (a, r) => a + r.total);
            return SdSection(
              title: l10n.feeRegisterTitle(items.length),
              trailing: Text(rupees(total), style: theme.textTheme.titleMedium),
              child: SdCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(items[i].studentName),
                      subtitle: Text([
                        items[i].serialLabel,
                        DateFormat('d MMM y').format(items[i].receivedOn),
                        if (items[i].classLabel.isNotEmpty) items[i].classLabel,
                        paymentModeLabel(l10n, items[i].mode),
                      ].join(' · ')),
                      trailing: items[i].isCancelled
                          ? StatusPill(text: l10n.certCancelled, color: sd.absent)
                          : Text(rupees(items[i].total), style: theme.textTheme.titleSmall),
                      onTap: () => context.go('/fees/receipt/${items[i].id}'),
                    ),
                  ],
                ]),
              ),
            );
          },
        ),
      ],
    );
  }
}
