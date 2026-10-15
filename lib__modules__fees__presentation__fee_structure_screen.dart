import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../application/fees_providers.dart';
import '../domain/fee_models.dart';

/// The amount per fee head that one class pays this year, for every student
/// or for one category only.
class FeeStructureScreen extends ConsumerStatefulWidget {
  const FeeStructureScreen({super.key, required this.programId, this.category});

  final String programId;
  final String? category;

  @override
  ConsumerState<FeeStructureScreen> createState() => _FeeStructureScreenState();
}

class _FeeStructureScreenState extends ConsumerState<FeeStructureScreen> {
  final Map<String, TextEditingController> _amounts = {};
  List<FeeHead> _heads = const [];
  FeeStructure? _existing;
  bool _loaded = false;
  bool _saving = false;

  /// Installments: (label, due date, total to be paid by then).
  final List<(TextEditingController, DateTime, TextEditingController)> _installments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _amounts.values) {
      c.dispose();
    }
    for (final (label, _, amount) in _installments) {
      label.dispose();
      amount.dispose();
    }
    super.dispose();
  }

  bool _matches(FeeStructure s) =>
      s.programId == widget.programId &&
      (s.category ?? '').toLowerCase() == (widget.category ?? '').trim().toLowerCase();

  Future<void> _load() async {
    final year = ref.read(academicControllerProvider).activeYear;
    if (year == null) return;
    final repo = ref.read(feeRepositoryProvider);
    final heads = await repo.heads();
    final existing = (await repo.structures(year.id)).where(_matches).firstOrNull;
    if (!mounted) return;
    final dates = existing == null ? const <FeeDueDate>[] : await repo.dueDates(existing.id);
    if (!mounted) return;
    for (final d in dates) {
      _installments.add((TextEditingController(text: d.label), d.dueDate, TextEditingController(text: '${d.amount}')));
    }
    final shown = heads.where((h) => h.isActive || (existing?.amounts.containsKey(h.id) ?? false)).toList();
    for (final h in shown) {
      final v = existing?.amounts[h.id];
      _amounts[h.id] = TextEditingController(text: v == null ? '' : '$v')..addListener(() => setState(() {}));
    }
    setState(() {
      _heads = shown;
      _existing = existing;
      _loaded = true;
    });
  }

  int get _total => _amounts.values.fold(0, (a, c) => a + (int.tryParse(c.text.trim()) ?? 0));

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final year = ref.read(academicControllerProvider).activeYear;
    if (year == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(feeRepositoryProvider);
      final id = await repo.saveStructure(
        academicYearId: year.id,
        programId: widget.programId,
        category: widget.category,
        amounts: {for (final e in _amounts.entries) e.key: int.tryParse(e.value.text.trim()) ?? 0},
      );
      await repo.saveDueDates(id, [
        for (final (label, date, amount) in _installments)
          if ((int.tryParse(amount.text.trim()) ?? 0) > 0)
            FeeDueDate(label: label.text, dueDate: date, amount: int.parse(amount.text.trim())),
      ]);
      ref.read(feesRevisionProvider.notifier).state++;
      if (mounted) {
        SdToast.show(context, l10n.feeStructureSaved);
        context.go('/fees/setup');
      }
    } catch (e) {
      if (mounted) SdToast.show(context, feeErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final existing = _existing;
    if (existing == null) return;
    final ok = await SdDialog.confirm(
      context,
      title: l10n.feeDeleteStructure,
      message: l10n.feeDeleteStructureBody,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(feeRepositoryProvider).deleteStructure(existing.id);
    ref.read(feesRevisionProvider.notifier).state++;
    if (mounted) context.go('/fees/setup');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final academic = ref.watch(academicControllerProvider);
    final program = academic.programs.where((p) => p.id == widget.programId).firstOrNull;
    final who = widget.category == null ? l10n.feeAllStudents : l10n.feeForCategory(widget.category!);

    return SdPage(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: SdSpace.lg),
        child: Row(children: [
          IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/fees/setup')),
          const SizedBox(width: SdSpace.xs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(program?.name ?? '', style: theme.textTheme.headlineSmall),
              Text('$who · ${academic.activeYear?.label ?? ''}', style: theme.textTheme.bodySmall),
            ]),
          ),
          if (_existing != null)
            IconButton(tooltip: l10n.feeDeleteStructure, icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ]),
      ),
      if (!_loaded)
        const SdSkeleton(height: 240)
      else ...[
        if (widget.category != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SdSpace.md),
            child: Text(l10n.feeCategoryHint(widget.category!), style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
          ),
        SdCard(
          child: Column(children: [
            for (final h in _heads)
              Padding(
                padding: const EdgeInsets.only(bottom: SdSpace.sm),
                child: Row(children: [
                  Expanded(child: Text(h.name, style: theme.textTheme.bodyMedium)),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _amounts[h.id],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(prefixText: '₹ ', hintText: '0', isDense: true),
                    ),
                  ),
                ]),
              ),
            const Divider(),
            Row(children: [
              Expanded(child: Text(l10n.reportTotal, style: theme.textTheme.titleSmall)),
              Text(rupees(_total), style: theme.textTheme.titleMedium),
            ]),
          ]),
        ),
        const SizedBox(height: SdSpace.xl),
        SdSection(
          title: l10n.feeInstallmentsTitle,
          trailing: SdButton(
            label: l10n.feeAddInstallment,
            icon: Icons.add,
            variant: SdButtonVariant.text,
            onPressed: () => setState(() {
              final n = _installments.length + 1;
              final now = DateTime.now();
              _installments.add((
                TextEditingController(text: l10n.feeInstallmentN(n)),
                DateTime(now.year, now.month + n, 1),
                TextEditingController(),
              ));
            }),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l10n.feeInstallmentsHint, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
            const SizedBox(height: SdSpace.sm),
            for (var i = 0; i < _installments.length; i++)
              SdCard(
                child: Column(children: [
                  Row(children: [
                    Expanded(child: TextField(controller: _installments[i].$1, decoration: InputDecoration(labelText: l10n.feeInstallmentName))),
                    IconButton(
                      tooltip: l10n.delete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        final removed = _installments[i];
                        setState(() => _installments.removeAt(i));
                        // Freed after the row has left the screen.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          removed.$1.dispose();
                          removed.$3.dispose();
                        });
                      },
                    ),
                  ]),
                  Row(children: [
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text(DateFormat('d MMM y').format(_installments[i].$2)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _installments[i].$2,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _installments[i] = (_installments[i].$1, picked, _installments[i].$3));
                          }
                        },
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: _installments[i].$3,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(prefixText: '₹ ', labelText: l10n.feeInstallmentTotal, isDense: true),
                      ),
                    ),
                  ]),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: SdSpace.xl),
        SdButton(label: l10n.save, icon: Icons.check, expand: true, onPressed: _saving ? null : _save),
      ],
    ]);
  }
}
