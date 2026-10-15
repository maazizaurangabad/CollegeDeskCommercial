import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../students/application/students_providers.dart';
import '../application/fees_providers.dart';
import '../domain/fee_models.dart';

/// Fee setup: receipt numbering, fee heads, and what each class pays this
/// year (for everyone, and optionally per category).
class FeeSetupScreen extends ConsumerStatefulWidget {
  const FeeSetupScreen({super.key});

  @override
  ConsumerState<FeeSetupScreen> createState() => _FeeSetupScreenState();
}

class _FeeSetupScreenState extends ConsumerState<FeeSetupScreen> {
  void _changed() {
    if (!mounted) return;
    ref.read(feesRevisionProvider.notifier).state++;
    setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _changed();
    } catch (e) {
      if (mounted) SdToast.show(context, feeErrorMessage(AppLocalizations.of(context), e));
    }
  }

  Future<void> _editPrefix(String current) async {
    final l10n = AppLocalizations.of(context);
    final value = await SdDialog.prompt(
      context,
      title: l10n.feeReceiptPrefix,
      label: l10n.feeReceiptPrefixHint,
      confirmLabel: l10n.save,
      cancelLabel: l10n.cancel,
      initial: current,
    );
    if (value == null) return;
    await _run(() => ref.read(feeRepositoryProvider).setReceiptPrefix(value));
  }

  Future<void> _addHead() async {
    final l10n = AppLocalizations.of(context);
    final name = await SdDialog.prompt(
      context,
      title: l10n.feeAddHead,
      label: l10n.feeHeadName,
      confirmLabel: l10n.save,
      cancelLabel: l10n.cancel,
    );
    if (name == null) return;
    await _run(() => ref.read(feeRepositoryProvider).addHead(name).then((_) {}));
  }

  Future<void> _headMenu(FeeHead h, String action) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(feeRepositoryProvider);
    switch (action) {
      case 'rename':
        final name = await SdDialog.prompt(
          context,
          title: l10n.feeRenameHead,
          label: l10n.feeHeadName,
          confirmLabel: l10n.save,
          cancelLabel: l10n.cancel,
          initial: h.name,
        );
        if (name != null) await _run(() => repo.updateHead(h.id, name: name));
      case 'up':
        await _run(() => repo.moveHead(h.id, -1));
      case 'down':
        await _run(() => repo.moveHead(h.id, 1));
      case 'delete':
        final ok = await SdDialog.confirm(
          context,
          title: l10n.feeDeleteHead,
          message: h.name,
          confirmLabel: l10n.delete,
          cancelLabel: l10n.cancel,
          destructive: true,
        );
        if (ok) await _run(() => repo.deleteHead(h.id));
    }
  }

  Future<void> _addCategory(String programId) async {
    final l10n = AppLocalizations.of(context);
    final categories = await ref.read(studentCategoriesProvider.future);
    if (!mounted) return;
    final picked = await SdSheet.show<String>(
      context,
      title: l10n.feeChooseCategory,
      builder: (sheet) => ListView(shrinkWrap: true, children: [
        for (final c in categories) ListTile(title: Text(c), onTap: () => Navigator.of(sheet).pop(c)),
      ]),
    );
    if (picked == null || !mounted) return;
    context.go('/fees/structure?program=$programId&category=${Uri.encodeComponent(picked)}');
  }

  Future<void> _copyFromYear(String toYearId) async {
    final l10n = AppLocalizations.of(context);
    final years = ref.read(academicControllerProvider).years.where((y) => y.id != toYearId).toList();
    final picked = await SdSheet.show<String>(
      context,
      title: l10n.feeCopyFromYear,
      builder: (sheet) => ListView(shrinkWrap: true, children: [
        for (final y in years) ListTile(title: Text(y.label), onTap: () => Navigator.of(sheet).pop(y.id)),
      ]),
    );
    if (picked == null || !mounted) return;
    try {
      final n = await ref.read(feeRepositoryProvider).copyStructures(fromYearId: picked, toYearId: toYearId);
      _changed();
      if (mounted) SdToast.show(context, l10n.feeCopied(n));
    } catch (e) {
      if (mounted) SdToast.show(context, feeErrorMessage(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final academic = ref.watch(academicControllerProvider);
    final year = academic.activeYear;
    final repo = ref.read(feeRepositoryProvider);
    ref.watch(feesRevisionProvider);

    return SdPage(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: SdSpace.lg),
        child: Row(children: [
          IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/fees')),
          const SizedBox(width: SdSpace.xs),
          Expanded(child: Text(l10n.feeSetup, style: theme.textTheme.headlineSmall)),
        ]),
      ),

      // Receipt numbers.
      FutureBuilder<String>(
        future: repo.receiptPrefix(),
        builder: (context, snapshot) {
          final prefix = snapshot.data ?? '';
          return SdCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.numbers),
              title: Text(l10n.feeReceiptPrefix),
              subtitle: Text(l10n.feeReceiptExample('$prefix/${year?.label ?? ''}/0001')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editPrefix(prefix),
            ),
          );
        },
      ),
      const SizedBox(height: SdSpace.xl),

      // Fee heads.
      FutureBuilder<List<FeeHead>>(
        future: repo.heads(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SdSkeleton(height: 160);
          final heads = snapshot.data!;
          return SdSection(
            title: l10n.feeHeadsTitle,
            trailing: SdButton(label: l10n.feeAddHead, icon: Icons.add, variant: SdButtonVariant.text, onPressed: _addHead),
            child: SdCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < heads.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      heads[i].name,
                      style: heads[i].isActive ? null : TextStyle(color: sd.textMuted, decoration: TextDecoration.lineThrough),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Switch(
                        value: heads[i].isActive,
                        onChanged: (on) => _run(() => repo.updateHead(heads[i].id, isActive: on)),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (a) => _headMenu(heads[i], a),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'rename', child: Text(l10n.feeRenameHead)),
                          if (i > 0) PopupMenuItem(value: 'up', child: Text(l10n.feeMoveUp)),
                          if (i < heads.length - 1) PopupMenuItem(value: 'down', child: Text(l10n.feeMoveDown)),
                          PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                        ],
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
      const SizedBox(height: SdSpace.xl),

      // What each class pays.
      if (year == null)
        SdEmptyState(icon: Icons.event_busy, title: l10n.feeErrNoYear, message: '')
      else
        FutureBuilder<List<FeeStructure>>(
          future: repo.structures(year.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SdSkeleton(height: 200);
            final all = snapshot.data!;
            return SdSection(
              title: l10n.feeStructuresTitle(year.label),
              trailing: academic.years.length > 1
                  ? SdButton(
                      label: l10n.feeCopyFromYear,
                      icon: Icons.copy_all_outlined,
                      variant: SdButtonVariant.text,
                      onPressed: () => _copyFromYear(year.id),
                    )
                  : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l10n.feeStructuresHint, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
                const SizedBox(height: SdSpace.md),
                if (academic.programs.isEmpty) Text(l10n.feeNoClasses, style: theme.textTheme.bodySmall),
                for (final p in academic.programs) ...[
                  Builder(builder: (context) {
                    final mine = all.where((s) => s.programId == p.id).toList();
                    final general = mine.where((s) => s.category == null).firstOrNull;
                    final byCategory = mine.where((s) => s.category != null).toList()
                      ..sort((a, b) => a.category!.compareTo(b.category!));
                    return SdCard(
                      padding: EdgeInsets.zero,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(SdSpace.lg, SdSpace.md, SdSpace.lg, 0),
                          child: Text(p.name, style: theme.textTheme.titleSmall),
                        ),
                        ListTile(
                          dense: true,
                          title: Text(l10n.feeAllStudents),
                          trailing: Text(
                            general == null ? l10n.feeNotSet : rupees(general.total),
                            style: theme.textTheme.titleSmall?.copyWith(color: general == null ? sd.leave : null),
                          ),
                          onTap: () => context.go('/fees/structure?program=${p.id}'),
                        ),
                        for (final s in byCategory)
                          ListTile(
                            dense: true,
                            title: Text(l10n.feeForCategory(s.category!)),
                            trailing: Text(rupees(s.total), style: theme.textTheme.titleSmall),
                            onTap: () => context.go(
                              '/fees/structure?program=${p.id}&category=${Uri.encodeComponent(s.category!)}',
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: SdSpace.sm, bottom: SdSpace.xs),
                            child: SdButton(
                              label: l10n.feeAddCategoryFees,
                              icon: Icons.add,
                              variant: SdButtonVariant.text,
                              onPressed: () => _addCategory(p.id),
                            ),
                          ),
                        ),
                      ]),
                    );
                  }),
                  const SizedBox(height: SdSpace.md),
                ],
              ]),
            );
          },
        ),
    ]);
  }
}
