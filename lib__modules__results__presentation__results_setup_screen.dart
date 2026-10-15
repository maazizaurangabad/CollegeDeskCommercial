import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../application/results_providers.dart';
import '../domain/result_models.dart';

/// Results setup: exams of the year, result rules, and subjects per class.
class ResultsSetupScreen extends ConsumerStatefulWidget {
  const ResultsSetupScreen({super.key});

  @override
  ConsumerState<ResultsSetupScreen> createState() => _ResultsSetupScreenState();
}

class _ResultsSetupScreenState extends ConsumerState<ResultsSetupScreen> {
  String? _programId;

  void _changed() {
    if (!mounted) return;
    ref.read(resultsRevisionProvider.notifier).state++;
    setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _changed();
    } catch (e) {
      if (mounted) SdToast.show(context, resultErrorMessage(AppLocalizations.of(context), e));
    }
  }

  Future<String?> _ask(String title, String label, {String? initial}) {
    final l10n = AppLocalizations.of(context);
    return SdDialog.prompt(context, title: title, label: label, confirmLabel: l10n.save, cancelLabel: l10n.cancel, initial: initial ?? '');
  }

  Future<void> _editSubject(String programId, {Subject? subject}) async {
    final l10n = AppLocalizations.of(context);
    final result = await SdSheet.show<_SubjectForm>(
      context,
      title: subject == null ? l10n.resAddSubject : l10n.resEditSubject,
      builder: (_) => _SubjectSheet(subject: subject),
    );
    if (result == null || !mounted) return;
    final repo = ref.read(resultRepositoryProvider);
    if (result.delete && subject != null) {
      await _run(() => repo.deleteSubject(subject.id));
      return;
    }
    await _run(() async {
      if (subject == null) {
        await repo.addSubject(
          programId: programId,
          name: result.name,
          columnName: result.column,
          isGrade: result.isGrade,
          maxMarks: result.max,
          passMarks: result.pass,
        );
      } else {
        await repo.updateSubject(
          subject.id,
          name: result.name,
          columnName: result.column,
          isGrade: result.isGrade,
          maxMarks: result.max,
          passMarks: result.pass,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final academic = ref.watch(academicControllerProvider);
    final year = academic.activeYear;
    final repo = ref.read(resultRepositoryProvider);
    ref.watch(resultsRevisionProvider);
    final programId = _programId ?? academic.programs.firstOrNull?.id;

    return SdPage(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: SdSpace.lg),
        child: Row(children: [
          IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/results')),
          const SizedBox(width: SdSpace.xs),
          Expanded(child: Text(l10n.resSetup, style: theme.textTheme.headlineSmall)),
        ]),
      ),

      // Exams.
      if (year != null)
        FutureBuilder<List<Exam>>(
          future: repo.exams(year.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SdSkeleton(height: 120);
            final exams = snapshot.data!;
            return SdSection(
              title: l10n.resExamsTitle(year.label),
              trailing: SdButton(
                label: l10n.resAddExam,
                icon: Icons.add,
                variant: SdButtonVariant.text,
                onPressed: () async {
                  final name = await _ask(l10n.resAddExam, l10n.resExamName);
                  if (name != null) await _run(() => repo.addExam(year.id, name).then((_) {}));
                },
              ),
              child: SdCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final e in exams)
                    ListTile(
                      title: Text(e.name),
                      subtitle: Text(e.countsInFinal ? l10n.resCountsInFinal : l10n.resNotInFinal),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(
                          value: e.countsInFinal,
                          onChanged: (v) => _run(() => repo.updateExam(e.id, countsInFinal: v)),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (a) async {
                            if (a == 'rename') {
                              final name = await _ask(l10n.feeRenameHead, l10n.resExamName, initial: e.name);
                              if (name != null) await _run(() => repo.updateExam(e.id, name: name));
                            } else {
                              await _run(() => repo.deleteExam(e.id));
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'rename', child: Text(l10n.feeRenameHead)),
                            PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                          ],
                        ),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, SdSpace.md),
                    child: Text(l10n.resFinalHint, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
                  ),
                ]),
              ),
            );
          },
        ),
      const SizedBox(height: SdSpace.xl),

      // Rules.
      FutureBuilder<ResultRules>(
        future: repo.rules(),
        builder: (context, snapshot) {
          final r = snapshot.data;
          if (r == null) return const SdSkeleton(height: 120);
          Future<void> setLimit(String title, double current, ResultRules Function(double v) apply) async {
            final v = await _ask(title, l10n.resPercentLabel, initial: current.toStringAsFixed(0));
            final n = double.tryParse(v ?? '');
            if (n != null && n >= 0 && n <= 100) await _run(() => repo.saveRules(apply(n)));
          }

          ResultRules copy({bool? whole, int? atkt, double? d, double? f, double? s}) => ResultRules(
                wholePercent: whole ?? r.wholePercent,
                atktSubjects: atkt ?? r.atktSubjects,
                distinction: d ?? r.distinction,
                firstClass: f ?? r.firstClass,
                secondClass: s ?? r.secondClass,
              );

          return SdSection(
            title: l10n.resRulesTitle,
            child: SdCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SwitchListTile(
                  title: Text(l10n.resWholePercent),
                  subtitle: Text(l10n.resWholePercentHint),
                  value: r.wholePercent,
                  onChanged: (v) => _run(() => repo.saveRules(copy(whole: v))),
                ),
                ListTile(
                  title: Text(l10n.resAtkt),
                  subtitle: Text(r.atktSubjects == 0 ? l10n.resAtktOff : l10n.resAtktOn(r.atktSubjects)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: r.atktSubjects <= 0 ? null : () => _run(() => repo.saveRules(copy(atkt: r.atktSubjects - 1))),
                    ),
                    Text('${r.atktSubjects}'),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: r.atktSubjects >= 5 ? null : () => _run(() => repo.saveRules(copy(atkt: r.atktSubjects + 1))),
                    ),
                  ]),
                ),
                ListTile(
                  title: Text(l10n.resDistinction),
                  trailing: Text('${r.distinction.toStringAsFixed(0)}%'),
                  onTap: () => setLimit(l10n.resDistinction, r.distinction, (v) => copy(d: v)),
                ),
                ListTile(
                  title: Text(l10n.resFirstClass),
                  trailing: Text('${r.firstClass.toStringAsFixed(0)}%'),
                  onTap: () => setLimit(l10n.resFirstClass, r.firstClass, (v) => copy(f: v)),
                ),
                ListTile(
                  title: Text(l10n.resSecondClass),
                  trailing: Text('${r.secondClass.toStringAsFixed(0)}%'),
                  onTap: () => setLimit(l10n.resSecondClass, r.secondClass, (v) => copy(s: v)),
                ),
              ]),
            ),
          );
        },
      ),
      const SizedBox(height: SdSpace.xl),

      // Subjects per class.
      SdSection(
        title: l10n.resSubjectsTitle,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l10n.resSubjectsHint, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
          const SizedBox(height: SdSpace.md),
          Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
            for (final p in academic.programs)
              ChoiceChip(label: Text(p.name), selected: p.id == programId, onSelected: (_) => setState(() => _programId = p.id)),
          ]),
          const SizedBox(height: SdSpace.md),
          if (programId == null)
            Text(l10n.feeNoClasses, style: theme.textTheme.bodySmall)
          else
            FutureBuilder<List<Subject>>(
              future: repo.subjects(programId: programId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SdSkeleton(height: 160);
                final columns = SubjectColumn.of(snapshot.data!);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (columns.isNotEmpty)
                    SdCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (var i = 0; i < columns.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(SdSpace.lg, SdSpace.sm, SdSpace.xs, 0),
                            child: Row(children: [
                              Expanded(
                                child: Text(
                                  columns[i].isGrade ? '${columns[i].name} (${l10n.resGrade})' : columns[i].name,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.feeMoveUp,
                                icon: const Icon(Icons.arrow_upward, size: 18),
                                onPressed: i == 0 ? null : () => _run(() => repo.moveColumn(programId, columns[i].name, -1)),
                              ),
                              IconButton(
                                tooltip: l10n.feeMoveDown,
                                icon: const Icon(Icons.arrow_downward, size: 18),
                                onPressed: i == columns.length - 1
                                    ? null
                                    : () => _run(() => repo.moveColumn(programId, columns[i].name, 1)),
                              ),
                            ]),
                          ),
                          for (final s in columns[i].subjects)
                            ListTile(
                              dense: true,
                              title: Text(s.name),
                              subtitle: Text(s.isGrade ? l10n.resGradeOnly : l10n.resMaxPass(s.maxMarks, s.passMarks)),
                              trailing: const Icon(Icons.edit_outlined, size: 18),
                              onTap: () => _editSubject(programId, subject: s),
                            ),
                        ],
                      ]),
                    ),
                  const SizedBox(height: SdSpace.sm),
                  Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
                    SdButton(label: l10n.resAddSubject, icon: Icons.add, onPressed: () => _editSubject(programId)),
                    SdButton(
                      label: l10n.resScienceTemplate,
                      icon: Icons.science_outlined,
                      variant: SdButtonVariant.secondary,
                      onPressed: () => _run(() async {
                        final n = await repo.addScienceTemplate(programId);
                        if (mounted) SdToast.show(context, l10n.resSubjectsAdded(n));
                      }),
                    ),
                    if (academic.programs.length > 1)
                      SdButton(
                        label: l10n.resCopySubjects,
                        icon: Icons.copy_all_outlined,
                        variant: SdButtonVariant.text,
                        onPressed: () async {
                          final from = await SdSheet.show<String>(
                            context,
                            title: l10n.resCopySubjects,
                            builder: (sheet) => ListView(shrinkWrap: true, children: [
                              for (final p in academic.programs.where((p) => p.id != programId))
                                ListTile(title: Text(p.name), onTap: () => Navigator.of(sheet).pop(p.id)),
                            ]),
                          );
                          if (from == null) return;
                          await _run(() async {
                            final n = await repo.copySubjects(fromProgramId: from, toProgramId: programId);
                            if (mounted) SdToast.show(context, l10n.resSubjectsAdded(n));
                          });
                        },
                      ),
                  ]),
                ]);
              },
            ),
        ]),
      ),
    ]);
  }
}

class _SubjectForm {
  const _SubjectForm({
    required this.name,
    required this.column,
    required this.isGrade,
    required this.max,
    required this.pass,
    this.delete = false,
  });

  final String name;
  final String column;
  final bool isGrade;
  final int max;
  final int pass;
  final bool delete;
}

class _SubjectSheet extends StatefulWidget {
  const _SubjectSheet({this.subject});

  final Subject? subject;

  @override
  State<_SubjectSheet> createState() => _SubjectSheetState();
}

class _SubjectSheetState extends State<_SubjectSheet> {
  late final _name = TextEditingController(text: widget.subject?.name ?? '');
  late final _column = TextEditingController(
    text: widget.subject == null || widget.subject!.columnName == widget.subject!.name ? '' : widget.subject!.columnName,
  );
  late final _max = TextEditingController(text: '${widget.subject?.isGrade == false ? widget.subject!.maxMarks : 100}');
  late final _pass = TextEditingController(text: '${widget.subject?.isGrade == false ? widget.subject!.passMarks : 35}');
  late bool _grade = widget.subject?.isGrade ?? false;

  @override
  void dispose() {
    _name.dispose();
    _column.dispose();
    _max.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _name, decoration: InputDecoration(labelText: l10n.resSubjectName)),
          const SizedBox(height: SdSpace.md),
          TextField(
            controller: _column,
            decoration: InputDecoration(labelText: l10n.resColumnName, helperText: l10n.resColumnHint, helperMaxLines: 3),
          ),
          const SizedBox(height: SdSpace.md),
          Wrap(spacing: SdSpace.sm, children: [
            ChoiceChip(label: Text(l10n.resKindMarks), selected: !_grade, onSelected: (_) => setState(() => _grade = false)),
            ChoiceChip(label: Text(l10n.resKindGrade), selected: _grade, onSelected: (_) => setState(() => _grade = true)),
          ]),
          if (!_grade) ...[
            const SizedBox(height: SdSpace.md),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: InputDecoration(labelText: l10n.resMaxMarks),
                ),
              ),
              const SizedBox(width: SdSpace.md),
              Expanded(
                child: TextField(
                  controller: _pass,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: InputDecoration(labelText: l10n.resPassMarks),
                ),
              ),
            ]),
          ],
          const SizedBox(height: SdSpace.lg),
          Wrap(spacing: SdSpace.sm, alignment: WrapAlignment.end, children: [
            if (widget.subject != null)
              SdButton(
                label: l10n.delete,
                variant: SdButtonVariant.text,
                onPressed: () => Navigator.of(context).pop(const _SubjectForm(name: '', column: '', isGrade: false, max: 0, pass: 0, delete: true)),
              ),
            SdButton(
              label: l10n.save,
              icon: Icons.check,
              onPressed: () => Navigator.of(context).pop(_SubjectForm(
                name: _name.text,
                column: _column.text,
                isGrade: _grade,
                max: int.tryParse(_max.text) ?? 100,
                pass: int.tryParse(_pass.text) ?? 35,
              )),
            ),
          ]),
        ]),
      ),
    );
  }
}
