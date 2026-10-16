import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/academic/academic_models.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../results/application/results_providers.dart';
import '../../results/domain/result_models.dart';
import '../application/students_providers.dart';
import '../presentation/student_labels.dart';
import 'promotion_models.dart';
import 'promotion_providers.dart';

/// Year-end promotion: choose next year, check each class, confirm.
/// Everything is done in one step that can be undone.
class PromotionScreen extends ConsumerStatefulWidget {
  const PromotionScreen({super.key});

  @override
  ConsumerState<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends ConsumerState<PromotionScreen> {
  String? _fromYearId;
  String? _toYearId;
  bool _promoteAtkt = true;
  RollOrder _rollOrder = RollOrder.byName;
  bool _copyFees = true;
  bool _makeActive = true;
  final _leaveReason = TextEditingController();

  List<PromotionCandidate>? _candidates;
  Map<String, String> _labels = const {};
  bool _busy = false;
  PromotionResult? _done;
  Future<List<PromotionBatch>>? _history;

  @override
  void initState() {
    super.initState();
    _history = ref.read(promotionRepositoryProvider).history();
  }

  @override
  void dispose() {
    _leaveReason.dispose();
    super.dispose();
  }

  bool get _canRun => ref.read(permissionCheckerProvider)('students.edit');

  Future<void> _load() async {
    final from = _fromYearId, to = _toYearId;
    if (from == null || to == null) return;
    setState(() {
      _busy = true;
      _done = null;
    });
    try {
      final list = await ref.read(promotionRepositoryProvider).candidates(
            fromYearId: from,
            toYearId: to,
            promoteAtkt: _promoteAtkt,
          );
      final labels = await ref.read(academicRepositoryProvider).divisionLabels();
      if (!mounted) return;
      setState(() {
        _candidates = list;
        _labels = labels;
      });
    } catch (_) {
      if (mounted) SdToast.show(context, AppLocalizations.of(context).p360LoadFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setNext(Program program, String? nextId) async {
    await ref.read(academicRepositoryProvider).setNextProgram(program.id, nextId);
    await ref.read(academicControllerProvider.notifier).reload();
    await _load();
  }

  Future<void> _commit() async {
    final l10n = AppLocalizations.of(context);
    final list = _candidates!;
    int count(PromotionAction a) => list.where((c) => c.action == a).length;
    final ok = await SdDialog.confirm(
      context,
      title: l10n.promoConfirmTitle,
      message: l10n.promoConfirm(
        count(PromotionAction.promote),
        count(PromotionAction.repeat),
        count(PromotionAction.leave),
        count(PromotionAction.skip),
      ),
      confirmLabel: l10n.promoRun,
      cancelLabel: l10n.cancel,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(promotionRepositoryProvider).commit(
            fromYearId: _fromYearId!,
            toYearId: _toYearId!,
            candidates: list,
            rollOrder: _rollOrder,
            leaveReason: _leaveReason.text.trim().isEmpty ? l10n.promoLeaveReasonDefault : _leaveReason.text.trim(),
            copyFees: _copyFees,
            makeActive: _makeActive,
          );
      ref.read(studentsRevisionProvider.notifier).state++;
      ref.read(resultsRevisionProvider.notifier).state++;
      await ref.read(academicControllerProvider.notifier).reload();
      if (!mounted) return;
      setState(() {
        _done = result;
        _candidates = null;
        _history = ref.read(promotionRepositoryProvider).history();
      });
    } catch (e) {
      if (mounted) SdToast.show(context, l10n.promoFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(String batchId) async {
    final l10n = AppLocalizations.of(context);
    final ok = await SdDialog.confirm(
      context,
      title: l10n.promoUndo,
      message: l10n.promoUndoConfirm,
      confirmLabel: l10n.promoUndo,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(promotionRepositoryProvider).undo(batchId);
    ref.read(studentsRevisionProvider.notifier).state++;
    ref.read(resultsRevisionProvider.notifier).state++;
    if (!mounted) return;
    SdToast.show(context, l10n.promoUndone);
    setState(() {
      _done = null;
      _history = ref.read(promotionRepositoryProvider).history();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final academic = ref.watch(academicControllerProvider);
    final years = [...academic.years]..sort((a, b) => a.startDate.compareTo(b.startDate));
    _fromYearId ??= academic.activeYear?.id;
    final from = years.where((y) => y.id == _fromYearId).firstOrNull;
    final later = years.where((y) => from != null && y.startDate.isAfter(from.startDate)).toList();
    if (_toYearId != null && !later.any((y) => y.id == _toYearId)) _toYearId = null;
    _toYearId ??= later.firstOrNull?.id;

    return SdPage(
      children: [
        Row(children: [
          IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/settings')),
          const SizedBox(width: SdSpace.xs),
          Expanded(child: Text(l10n.promoTitle, style: theme.textTheme.headlineSmall)),
        ]),
        const SizedBox(height: SdSpace.sm),
        Text(l10n.promoIntro, style: theme.textTheme.bodyMedium?.copyWith(color: sd.textMuted)),
        const SizedBox(height: SdSpace.lg),
        if (_done != null) _resultCard(l10n, _done!),
        SdSection(
          title: l10n.promoSetup,
          child: SdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(spacing: SdSpace.md, runSpacing: SdSpace.md, children: [
                  SizedBox(
                    width: 240,
                    child: SdSelectField<String>(
                      label: l10n.promoFrom,
                      value: _fromYearId,
                      options: [for (final y in years) (y.id, y.label)],
                      onChanged: (v) => setState(() {
                        _fromYearId = v;
                        _toYearId = null;
                        _candidates = null;
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: SdSelectField<String>(
                      label: l10n.promoTo,
                      value: _toYearId,
                      options: [for (final y in later) (y.id, y.label)],
                      onChanged: (v) => setState(() {
                        _toYearId = v;
                        _candidates = null;
                      }),
                    ),
                  ),
                ]),
                if (later.isEmpty) ...[
                  const SizedBox(height: SdSpace.md),
                  ProfileHint(text: l10n.promoNoNextYear),
                  const SizedBox(height: SdSpace.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SdButton(
                      label: l10n.promoAddYear,
                      icon: Icons.add,
                      variant: SdButtonVariant.secondary,
                      onPressed: () => context.go('/settings/academic-years'),
                    ),
                  ),
                ],
                const SizedBox(height: SdSpace.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.promoAtkt),
                  subtitle: Text(l10n.promoAtktHint),
                  value: _promoteAtkt,
                  onChanged: (v) => setState(() {
                    _promoteAtkt = v;
                    _candidates = null;
                  }),
                ),
                SizedBox(
                  width: 320,
                  child: SdSelectField<RollOrder>(
                    label: l10n.promoRolls,
                    value: _rollOrder,
                    options: [
                      (RollOrder.byName, l10n.promoRollsName),
                      (RollOrder.byGr, l10n.promoRollsGr),
                      (RollOrder.keep, l10n.promoRollsKeep),
                    ],
                    onChanged: (v) => setState(() => _rollOrder = v ?? RollOrder.byName),
                  ),
                ),
                TextField(
                  controller: _leaveReason,
                  decoration: InputDecoration(labelText: l10n.promoLeaveReason, hintText: l10n.promoLeaveReasonDefault),
                ),
                const SizedBox(height: SdSpace.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.promoCopyFees),
                  subtitle: Text(l10n.promoCopyFeesHint),
                  value: _copyFees,
                  onChanged: (v) => setState(() => _copyFees = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.promoMakeActive),
                  subtitle: Text(l10n.promoMakeActiveHint),
                  value: _makeActive,
                  onChanged: (v) => setState(() => _makeActive = v),
                ),
                const SizedBox(height: SdSpace.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SdButton(
                    label: l10n.promoLoad,
                    icon: Icons.playlist_add_check,
                    onPressed: _busy || _toYearId == null || !_canRun ? null : _load,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_busy) const Padding(padding: EdgeInsets.only(top: SdSpace.lg), child: LinearProgressIndicator()),
        if (_candidates != null) ..._preview(l10n, academic, _candidates!),
        const SizedBox(height: SdSpace.xl),
        _historyCard(l10n),
      ],
    );
  }

  List<Widget> _preview(AppLocalizations l10n, AcademicSnapshot academic, List<PromotionCandidate> list) {
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final programs = {for (final p in academic.programs) p.id: p};
    if (list.isEmpty) {
      return [
        const SizedBox(height: SdSpace.lg),
        SdEmptyState(icon: Icons.groups_outlined, title: l10n.promoNobody, message: l10n.promoNobodyHint),
      ];
    }
    int count(PromotionAction a) => list.where((c) => c.action == a).length;
    final byDivision = <String, List<PromotionCandidate>>{};
    for (final c in list) {
      (byDivision[c.fromDivisionId] ??= []).add(c);
    }
    final noResult = list.where((c) => c.noResult).length;
    return [
      const SizedBox(height: SdSpace.xl),
      SdSection(
        title: l10n.promoCheck,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
              StatusPill(text: l10n.promoCountPromote(count(PromotionAction.promote)), color: sd.present),
              StatusPill(text: l10n.promoCountRepeat(count(PromotionAction.repeat)), color: sd.absent),
              StatusPill(text: l10n.promoCountLeave(count(PromotionAction.leave)), color: sd.info),
              StatusPill(text: l10n.promoCountSkip(count(PromotionAction.skip)), color: sd.textMuted),
              if (noResult > 0) StatusPill(text: l10n.promoCountNoResult(noResult), color: sd.leave),
            ]),
            const SizedBox(height: SdSpace.sm),
            Text(l10n.promoCheckHint, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
            const SizedBox(height: SdSpace.md),
            for (final entry in byDivision.entries)
              _classCard(l10n, programs, entry.key, entry.value),
            Align(
              alignment: Alignment.centerLeft,
              child: SdButton(
                label: l10n.promoRun,
                icon: Icons.upgrade,
                onPressed: _busy || !_canRun ? null : _commit,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _classCard(AppLocalizations l10n, Map<String, Program> programs, String divisionId, List<PromotionCandidate> list) {
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final program = programs[list.first.fromProgramId];
    final next = list.first.nextProgramId == null ? null : programs[list.first.nextProgramId];
    final hasNext = next != null;
    final label = _labels[divisionId] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  '$label  →  ${hasNext ? '${next.name} ${list.first.divisionName}' : l10n.promoLastClass}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              PopupMenuButton<PromotionAction>(
                tooltip: l10n.promoSetAll,
                icon: const Icon(Icons.checklist),
                onSelected: (a) => setState(() {
                  for (final c in list) {
                    if (a != PromotionAction.promote || c.hasNext) c.action = a;
                  }
                }),
                itemBuilder: (_) => [
                  for (final a in PromotionAction.values)
                    if (a != PromotionAction.promote || hasNext)
                      PopupMenuItem(value: a, child: Text(l10n.promoSetAllTo(_actionLabel(l10n, a)))),
                ],
              ),
            ]),
            if (program != null)
              Padding(
                padding: const EdgeInsets.only(top: SdSpace.xs, bottom: SdSpace.sm),
                child: SizedBox(
                  width: 320,
                  child: SdSelectField<String>(
                    label: l10n.promoNextClass(program.name),
                    value: program.nextProgramId,
                    options: [
                      for (final p in programs.values)
                        if (p.id != program.id) (p.id, p.name),
                    ],
                    clearLabel: l10n.promoNoNext,
                    onChanged: (v) => _setNext(program, v),
                  ),
                ),
              ),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SdSpace.xs),
                child: Row(children: [
                  SizedBox(
                    width: 36,
                    child: Text(c.roll?.toString() ?? '', style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name, style: theme.textTheme.bodyMedium),
                      if ((c.grNumber ?? '').isNotEmpty)
                        Text('${l10n.idGr} ${c.grNumber}', style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
                    ]),
                  ),
                  StatusPill(
                    text: c.noResult ? l10n.promoNoResult : resultStatusLabel(l10n, c.result!),
                    color: switch (c.result) {
                      ResultStatus.passed => sd.present,
                      ResultStatus.failed => sd.absent,
                      ResultStatus.atkt => sd.leave,
                      _ => sd.leave,
                    },
                  ),
                  const SizedBox(width: SdSpace.sm),
                  SizedBox(
                    width: 170,
                    child: SdSelectField<PromotionAction>(
                      label: l10n.promoAction,
                      value: c.action,
                      options: [
                        for (final a in PromotionAction.values)
                          if (a != PromotionAction.promote || c.hasNext) (a, _actionLabel(l10n, a)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => c.action = v);
                      },
                    ),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  String _actionLabel(AppLocalizations l10n, PromotionAction a) => switch (a) {
        PromotionAction.promote => l10n.promoActionPromote,
        PromotionAction.repeat => l10n.promoActionRepeat,
        PromotionAction.leave => l10n.promoActionLeave,
        PromotionAction.skip => l10n.promoActionSkip,
      };

  Widget _resultCard(AppLocalizations l10n, PromotionResult r) {
    final sd = SdColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.xl),
      child: SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.task_alt, color: sd.present),
              const SizedBox(width: SdSpace.sm),
              Expanded(child: Text(l10n.promoDone, style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: SdSpace.sm),
            Text(l10n.promoDoneSummary(r.promoted, r.repeated, r.left, r.skipped)),
            if (r.feesCopied > 0) Text(l10n.promoFeesCopied(r.feesCopied)),
            const SizedBox(height: SdSpace.md),
            Wrap(spacing: SdSpace.sm, children: [
              SdButton(label: l10n.importOpenStudents, onPressed: () => context.go('/students')),
              SdButton(label: l10n.promoUndo, variant: SdButtonVariant.text, onPressed: () => _undo(r.batchId)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(AppLocalizations l10n) {
    return FutureBuilder<List<PromotionBatch>>(
      future: _history,
      builder: (context, snapshot) {
        final list = snapshot.data ?? const <PromotionBatch>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return SdSection(
          title: l10n.promoHistory,
          child: SdCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final b in list)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(b.label),
                  subtitle: Text(
                    '${DateFormat('d MMM y, h:mm a').format(b.createdAt.toLocal())} · '
                    '${l10n.promoDoneSummary(b.promoted, b.repeated, b.left, 0)}',
                  ),
                  trailing: b.undone
                      ? StatusPill(text: l10n.promoUndoneShort, color: SdColors.of(context).textMuted)
                      : TextButton(onPressed: _canRun ? () => _undo(b.id) : null, child: Text(l10n.promoUndo)),
                ),
            ]),
          ),
        );
      },
    );
  }
}

/// A short note inside a card.
class ProfileHint extends StatelessWidget {
  const ProfileHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 18, color: SdColors.of(context).leave),
        const SizedBox(width: SdSpace.sm),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]);
}
