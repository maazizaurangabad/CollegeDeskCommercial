import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../students/application/students_providers.dart';
import '../../students/domain/student_models.dart';
import '../../students/presentation/student_labels.dart';
import '../application/fees_providers.dart';
import '../domain/fee_models.dart';

/// Take a payment: choose the student, type the amount received (it is
/// shared over the heads, which can be changed), how it was paid, save.
class FeePaymentScreen extends ConsumerStatefulWidget {
  const FeePaymentScreen({super.key, this.studentId});

  final String? studentId;

  @override
  ConsumerState<FeePaymentScreen> createState() => _FeePaymentScreenState();
}

class _FeePaymentScreenState extends ConsumerState<FeePaymentScreen> {
  String _query = '';
  FeeAccount? _account;
  List<FeeHead> _heads = const [];
  final _received = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  final Map<String, TextEditingController> _byHead = {};
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = DateTime.now();
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.studentId != null) _load(widget.studentId!);
  }

  @override
  void dispose() {
    _received.dispose();
    _reference.dispose();
    _note.dispose();
    for (final c in _byHead.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load(String studentId) async {
    final year = ref.read(academicControllerProvider).activeYear;
    if (year == null) return;
    try {
      final repo = ref.read(feeRepositoryProvider);
      final account = await repo.account(studentId, year.id);
      final heads = await repo.heads();
      if (!mounted) return;
      for (final c in _byHead.values) {
        c.dispose();
      }
      _byHead.clear();
      for (final id in _headIds(account, heads)) {
        _byHead[id] = TextEditingController()..addListener(_refresh);
      }
      setState(() {
        _account = account;
        _heads = heads;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _refresh() => setState(() {});

  /// Heads on the student's account first, then the other active heads.
  static List<String> _headIds(FeeAccount a, List<FeeHead> heads) => [
        for (final l in a.lines) l.headId,
        for (final h in heads)
          if (h.isActive && !a.lines.any((l) => l.headId == h.id)) h.id,
      ];

  int _amount(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int get _total => _byHead.values.fold(0, (a, c) => a + _amount(c));

  void _share(String text) {
    final account = _account;
    if (account == null) return;
    final split = account.allocate(int.tryParse(text.trim()) ?? 0);
    for (final e in _byHead.entries) {
      final v = split.byHead[e.key] ?? 0;
      e.value.text = v == 0 ? '' : '$v';
    }
    // What is more than the balance goes to the first head, so nothing is lost.
    if (split.rest > 0 && _byHead.isNotEmpty) {
      final first = _byHead.entries.first;
      first.value.text = '${_amount(first.value) + split.rest}';
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final account = _account!;
    final total = _total;
    if (total <= 0) {
      SdToast.show(context, l10n.feeErrNoAmount);
      return;
    }
    if (total > account.balance) {
      final ok = await SdDialog.confirm(
        context,
        title: l10n.feeMoreThanDueTitle,
        message: l10n.feeMoreThanDueBody(rupees(total), rupees(account.balance < 0 ? 0 : account.balance)),
        confirmLabel: l10n.feeSaveAnyway,
        cancelLabel: l10n.cancel,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref.read(feeRepositoryProvider).takePayment(
            studentId: account.studentId,
            academicYearId: account.academicYearId,
            byHead: {for (final e in _byHead.entries) e.key: _amount(e.value)},
            mode: _mode,
            receivedOn: _date,
            reference: _mode.needsReference ? _reference.text : null,
            note: _note.text,
          );
      ref.read(feesRevisionProvider.notifier).state++;
      if (mounted) context.go('/fees/receipt/$id');
    } catch (e) {
      if (mounted) SdToast.show(context, feeErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final academic = ref.watch(academicControllerProvider);
    final year = academic.activeYear;

    Widget header() => Padding(
          padding: const EdgeInsets.only(bottom: SdSpace.lg),
          child: Row(children: [
            IconButton(
              tooltip: l10n.back,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go(widget.studentId == null ? '/fees' : '/fees/student/${widget.studentId}'),
            ),
            const SizedBox(width: SdSpace.xs),
            Expanded(child: Text(l10n.feeTakePayment, style: theme.textTheme.headlineSmall)),
          ]),
        );

    if (year == null) {
      return SdPage(children: [header(), SdEmptyState(icon: Icons.event_busy, title: l10n.feeErrNoYear, message: '')]);
    }

    // Step 1: choose the student.
    if (widget.studentId == null) {
      return SdPage(children: [
        header(),
        SdTextField(
          hint: l10n.feeFindStudent,
          prefixIcon: Icons.search,
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: SdSpace.md),
        if (_query.length >= 2)
          FutureBuilder<List<StudentListItem>>(
            future: ref.read(studentRepositoryProvider).list(query: _query, academicYearId: year.id, limit: 20),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <StudentListItem>[];
              return SdCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final s in items)
                    ListTile(
                      title: Text(s.fullName),
                      subtitle: Text([s.displayCode, placementName(academic, s.divisionId) ?? ''].join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/fees/pay?student=${s.id}'),
                    ),
                ]),
              );
            },
          )
        else
          Text(l10n.feeFindStudentHint, style: theme.textTheme.bodySmall),
      ]);
    }

    final account = _account;
    if (_error != null) {
      return SdPage(children: [header(), Text(feeErrorMessage(l10n, _error!))]);
    }
    if (account == null) {
      return SdPage(children: [header(), const SdSkeleton(height: 240)]);
    }
    final sd = SdColors.of(context);
    final names = {for (final h in _heads) h.id: h.name};
    final lineOf = {for (final l in account.lines) l.headId: l};

    return SdPage(children: [
      header(),
      FeeAccountSummary(account: account),
      if (!account.hasStructure) ...[
        const SizedBox(height: SdSpace.md),
        Container(
          padding: const EdgeInsets.all(SdSpace.md),
          decoration: BoxDecoration(color: sd.leave.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(SdRadius.sm)),
          child: Row(children: [
            Expanded(child: Text(l10n.feeNoStructureWarning, style: theme.textTheme.bodySmall?.copyWith(color: sd.leave))),
            SdButton(label: l10n.feeSetup, variant: SdButtonVariant.text, onPressed: () => context.go('/fees/setup')),
          ]),
        ),
      ],
      const SizedBox(height: SdSpace.xl),
      TextField(
        controller: _received,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: theme.textTheme.titleLarge,
        decoration: InputDecoration(labelText: l10n.feeAmountReceived, prefixText: '₹ ', helperText: l10n.feeAmountHint),
        onChanged: _share,
      ),
      const SizedBox(height: SdSpace.lg),
      SdSection(
        title: l10n.feeByHead,
        trailing: Text('${l10n.reportTotal}: ${rupees(_total)}', style: theme.textTheme.titleSmall),
        child: SdCard(
          child: Column(children: [
            for (final e in _byHead.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: SdSpace.sm),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(names[e.key] ?? lineOf[e.key]?.headName ?? '', style: theme.textTheme.bodyMedium),
                      Text(
                        l10n.feeBalanceIs(rupees(lineOf[e.key]?.balance ?? 0)),
                        style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted),
                      ),
                    ]),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: e.value,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(prefixText: '₹ ', isDense: true),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: SdSpace.lg),
      Text(l10n.feePaidBy, style: theme.textTheme.titleSmall),
      const SizedBox(height: SdSpace.sm),
      Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
        for (final m in PaymentMode.values)
          ChoiceChip(label: Text(paymentModeLabel(l10n, m)), selected: _mode == m, onSelected: (_) => setState(() => _mode = m)),
      ]),
      if (_mode.needsReference) ...[
        const SizedBox(height: SdSpace.md),
        SdTextField(controller: _reference, label: l10n.feeReference),
      ],
      const SizedBox(height: SdSpace.md),
      Row(children: [
        Expanded(
          child: Text('${l10n.feeReceivedOn}: ${DateFormat('d MMM y').format(_date)}', style: theme.textTheme.bodyMedium),
        ),
        SdButton(
          label: l10n.feeChangeDate,
          variant: SdButtonVariant.text,
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _date = picked);
          },
        ),
      ]),
      const SizedBox(height: SdSpace.sm),
      SdTextField(controller: _note, label: l10n.feeNote),
      const SizedBox(height: SdSpace.xl),
      SdButton(
        label: l10n.feeSaveReceipt(rupees(_total)),
        icon: Icons.check,
        expand: true,
        onPressed: _saving || _total <= 0 ? null : _save,
      ),
    ]);
  }
}

/// Name, class, and due / paid / balance at a glance.
class FeeAccountSummary extends StatelessWidget {
  const FeeAccountSummary({super.key, required this.account});

  final FeeAccount account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    return SdCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(account.studentName, style: theme.textTheme.titleMedium),
        Text(
          [
            account.classLabel,
            if ((account.grNumber ?? '').isNotEmpty) 'GR ${account.grNumber}',
            if ((account.category ?? '').isNotEmpty) account.category!,
            account.academicYearLabel,
          ].where((s) => s.isNotEmpty).join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: SdSpace.md),
        Row(children: [
          Expanded(child: _Figure(label: l10n.feeDue, value: rupees(account.due))),
          Expanded(child: _Figure(label: l10n.feePaid, value: rupees(account.paid), color: sd.present)),
          Expanded(
            child: _Figure(
              label: l10n.feeBalance,
              value: rupees(account.balance),
              color: account.balance > 0 ? sd.absent : sd.present,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: theme.textTheme.bodySmall),
      Text(value, style: theme.textTheme.titleMedium?.copyWith(color: color)),
    ]);
  }
}
