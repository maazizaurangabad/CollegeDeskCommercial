import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../students/presentation/student_labels.dart';
import '../application/fees_providers.dart';
import '../domain/fee_models.dart';
import 'fee_payment_screen.dart';

/// One student's fees for the active year: head-wise due, paid and balance,
/// concessions, and receipts.
class FeeStudentScreen extends ConsumerStatefulWidget {
  const FeeStudentScreen({super.key, required this.studentId});

  final String studentId;

  @override
  ConsumerState<FeeStudentScreen> createState() => _FeeStudentScreenState();
}

class _FeeStudentScreenState extends ConsumerState<FeeStudentScreen> {
  Future<FeeAccount>? _account;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final year = ref.read(academicControllerProvider).activeYear;
    if (year == null) return;
    _account = ref.read(feeRepositoryProvider).account(widget.studentId, year.id);
    if (mounted) setState(() {});
  }

  Future<void> _addAdjustment(FeeAccount a) async {
    final l10n = AppLocalizations.of(context);
    final heads = (await ref.read(feeRepositoryProvider).heads()).where((h) => h.isActive).toList();
    if (!mounted || heads.isEmpty) return;
    final result = await SdSheet.show<(String, int, String)>(
      context,
      title: l10n.feeAddAdjustment,
      builder: (_) => _AdjustmentSheet(heads: heads),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(feeRepositoryProvider).addAdjustment(
            studentId: a.studentId,
            academicYearId: a.academicYearId,
            headId: result.$1,
            amount: result.$2,
            reason: result.$3,
          );
      ref.read(feesRevisionProvider.notifier).state++;
      _reload();
    } catch (e) {
      if (mounted) SdToast.show(context, feeErrorMessage(l10n, e));
    }
  }

  Future<void> _removeAdjustment(FeeAdjustment adj) async {
    final l10n = AppLocalizations.of(context);
    final ok = await SdDialog.confirm(
      context,
      title: l10n.feeRemoveAdjustment,
      message: '${adj.headName}: ${rupees(adj.amount)} – ${adj.reason}',
      confirmLabel: l10n.feeRemoveAdjustment,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(feeRepositoryProvider).deleteAdjustment(adj.id);
      ref.read(feesRevisionProvider.notifier).state++;
      _reload();
    } catch (e) {
      if (mounted) SdToast.show(context, feeErrorMessage(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);

    Widget header() => Padding(
          padding: const EdgeInsets.only(bottom: SdSpace.lg),
          child: Row(children: [
            IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/fees')),
            const SizedBox(width: SdSpace.xs),
            Expanded(child: Text(l10n.feeStudentTitle, style: theme.textTheme.headlineSmall)),
            SdButton(
              label: l10n.feeTakePayment,
              icon: Icons.add,
              onPressed: () => context.go('/fees/pay?student=${widget.studentId}'),
            ),
          ]),
        );

    if (_account == null) {
      return SdPage(children: [header(), SdEmptyState(icon: Icons.event_busy, title: l10n.feeErrNoYear, message: '')]);
    }

    return SdPage(children: [
      header(),
      FutureBuilder<FeeAccount>(
        future: _account,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(feeErrorMessage(l10n, snapshot.error!));
          if (!snapshot.hasData) return const SdSkeleton(height: 240);
          final a = snapshot.data!;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FeeAccountSummary(account: a),
            const SizedBox(height: SdSpace.sm),
            Text(
              !a.hasStructure
                  ? l10n.feeNoStructureWarning
                  : (a.structureCategory == null ? l10n.feeUsingGeneral : l10n.feeUsingCategory(a.structureCategory!)),
              style: theme.textTheme.bodySmall?.copyWith(color: a.hasStructure ? sd.textMuted : sd.leave),
            ),
            if (a.overdue > 0 || a.nextDue != null) ...[
              const SizedBox(height: SdSpace.xs),
              Text(
                [
                  if (a.overdue > 0) '${l10n.feeOverdue}: ${rupees(a.overdue)}',
                  if (a.nextDue != null)
                    l10n.feeNextInstallment(
                      a.nextDue!.label,
                      DateFormat('d MMM y').format(a.nextDue!.dueDate),
                      rupees(a.nextDue!.amount),
                    ),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: a.overdue > 0 ? sd.absent : sd.textMuted),
              ),
            ],
            const SizedBox(height: SdSpace.xl),
            if (a.lines.isNotEmpty)
              SdSection(
                title: l10n.feeByHead,
                child: SdCard(
                  padding: EdgeInsets.zero,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: SdSpace.lg,
                      columns: [
                        DataColumn(label: Text(l10n.feeHead)),
                        DataColumn(label: Text(l10n.feeDue), numeric: true),
                        DataColumn(label: Text(l10n.feePaid), numeric: true),
                        DataColumn(label: Text(l10n.feeBalance), numeric: true),
                      ],
                      rows: [
                        for (final l in a.lines)
                          DataRow(cells: [
                            DataCell(Text(l.headName)),
                            DataCell(Text(
                              l.adjustment == 0
                                  ? rupees(l.due)
                                  : '${rupees(l.due)} (${l.adjustment > 0 ? '+' : ''}${Rupees.format(l.adjustment)})',
                            )),
                            DataCell(Text(rupees(l.paid))),
                            DataCell(Text(
                              rupees(l.balance),
                              style: TextStyle(color: l.balance > 0 ? sd.absent : null, fontWeight: FontWeight.w600),
                            )),
                          ]),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: SdSpace.xl),
            SdSection(
              title: l10n.feeAdjustmentsTitle,
              trailing: SdButton(
                label: l10n.feeAddAdjustment,
                icon: Icons.add,
                variant: SdButtonVariant.text,
                onPressed: () => _addAdjustment(a),
              ),
              child: a.adjustments.isEmpty
                  ? Text(l10n.feeNoAdjustments, style: theme.textTheme.bodySmall)
                  : SdCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (final adj in a.adjustments)
                          ListTile(
                            leading: Icon(
                              adj.amount < 0 ? Icons.remove_circle_outline : Icons.add_circle_outline,
                              color: adj.amount < 0 ? sd.present : sd.absent,
                            ),
                            title: Text('${adj.headName}: ${adj.amount > 0 ? '+' : ''}${rupees(adj.amount)}'),
                            subtitle: Text('${adj.reason} · ${DateFormat('d MMM y').format(adj.createdAt.toLocal())}'),
                            trailing: IconButton(
                              tooltip: l10n.feeRemoveAdjustment,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _removeAdjustment(adj),
                            ),
                          ),
                      ]),
                    ),
            ),
            const SizedBox(height: SdSpace.xl),
            SdSection(
              title: l10n.feeReceiptsTitle(a.receipts.length),
              child: a.receipts.isEmpty
                  ? Text(l10n.feeNoReceipts, style: theme.textTheme.bodySmall)
                  : SdCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (final r in a.receipts)
                          ListTile(
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: Text('${r.serialLabel} · ${rupees(r.total)}'),
                            subtitle: Text([
                              DateFormat('d MMM y').format(r.receivedOn),
                              paymentModeLabel(l10n, r.mode),
                              r.lines.map((l) => l.headName).join(', '),
                            ].join(' · ')),
                            trailing: r.isCancelled
                                ? StatusPill(text: l10n.certCancelled, color: sd.absent)
                                : const Icon(Icons.chevron_right),
                            onTap: () => context.go('/fees/receipt/${r.id}'),
                          ),
                      ]),
                    ),
            ),
          ]);
        },
      ),
    ]);
  }
}

/// Head, concession or extra, amount and reason. Pops (headId, signed amount, reason).
class _AdjustmentSheet extends StatefulWidget {
  const _AdjustmentSheet({required this.heads});

  final List<FeeHead> heads;

  @override
  State<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends State<_AdjustmentSheet> {
  late String _headId = widget.heads.first.id;
  bool _concession = true;
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: SdSpace.sm, children: [
            ChoiceChip(
              label: Text(l10n.feeConcession),
              selected: _concession,
              onSelected: (_) => setState(() => _concession = true),
            ),
            ChoiceChip(
              label: Text(l10n.feeExtraCharge),
              selected: !_concession,
              onSelected: (_) => setState(() => _concession = false),
            ),
          ]),
          const SizedBox(height: SdSpace.md),
          SdSelectField<String>(
            label: l10n.feeHead,
            value: _headId,
            options: [for (final h in widget.heads) (h.id, h.name)],
            onChanged: (v) => setState(() => _headId = v ?? _headId),
          ),
          const SizedBox(height: SdSpace.md),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: l10n.feeAmount, prefixText: '₹ '),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: SdSpace.md),
          TextField(
            controller: _reason,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.feeReason, hintText: l10n.feeReasonHint),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: SdSpace.lg),
          SdButton(
            label: l10n.save,
            icon: Icons.check,
            onPressed: amount <= 0 || _reason.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop((_headId, _concession ? -amount : amount, _reason.text.trim())),
          ),
        ]),
      ),
    );
  }
}
