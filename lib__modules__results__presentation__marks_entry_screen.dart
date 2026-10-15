import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../application/results_providers.dart';
import '../data/result_repository.dart';
import '../domain/result_models.dart';

/// Marks entry for one exam and class, one subject column at a time.
/// Type marks down the roll list; AB for absent; letters for grade subjects.
class MarksEntryScreen extends ConsumerStatefulWidget {
  const MarksEntryScreen({super.key, required this.examId, required this.divisionId});

  final String examId;
  final String divisionId;

  @override
  ConsumerState<MarksEntryScreen> createState() => _MarksEntryScreenState();
}

class _MarksEntryScreenState extends ConsumerState<MarksEntryScreen> {
  bool _loaded = false;
  bool _saving = false;
  Exam? _exam;
  List<Exam> _exams = const [];
  List<SubjectColumn> _columns = const [];
  List<RosterStudent> _roster = const [];
  Map<String, Map<String, String>> _choices = {};
  String? _column;

  /// "studentId|subjectId" -> box. Created as columns are opened.
  final Map<String, TextEditingController> _boxes = {};
  final Map<String, String> _saved = {};
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _boxes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final academic = ref.read(academicControllerProvider);
    final year = academic.activeYear;
    final division = academic.divisions.where((d) => d.id == widget.divisionId).firstOrNull;
    if (year == null || division == null) return;
    final repo = ref.read(resultRepositoryProvider);
    final exams = await repo.exams(year.id);
    final columns = SubjectColumn.of(await repo.subjects(programId: division.programId));
    final roster = await repo.roster(widget.divisionId, year.id);
    final ids = roster.map((r) => r.id);
    final choices = await repo.choices(year.id, ids);
    final marks = await repo.marks([widget.examId], ids);
    if (!mounted) return;
    for (final st in roster) {
      for (final c in columns) {
        for (final s in c.subjects) {
          final text = marks[widget.examId]?[st.id]?[s.id]?.text ?? '';
          final key = '${st.id}|${s.id}';
          _saved[key] = text;
          _boxes[key] = TextEditingController(text: text);
        }
      }
    }
    setState(() {
      _exams = exams;
      _exam = exams.where((e) => e.id == widget.examId).firstOrNull;
      _columns = columns;
      _roster = roster;
      _choices = choices;
      _column = columns.isEmpty ? null : columns.first.name;
      _loaded = true;
    });
  }

  /// The subject a student takes in a column: saved choice, else the one
  /// with marks typed, else the only subject.
  Subject? _subjectOf(String studentId, SubjectColumn c) {
    if (!c.isChoice) return c.subjects.first;
    final chosen = _choices[studentId]?[c.name];
    final s = c.subjects.where((s) => s.id == chosen).firstOrNull;
    if (s != null) return s;
    for (final s in c.subjects) {
      if ((_boxes['$studentId|${s.id}']?.text ?? '').trim().isNotEmpty) return s;
    }
    return null;
  }

  Future<void> _choose(Iterable<String> studentIds, SubjectColumn c, Subject s) async {
    final year = ref.read(academicControllerProvider).activeYear;
    if (year == null) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(resultRepositoryProvider).setChoice(
            academicYearId: year.id,
            studentIds: studentIds,
            columnName: c.name,
            subjectId: s.id,
          );
      if (!mounted) return;
      setState(() {
        for (final id in studentIds) {
          // Marks typed under another subject of the column move with the choice.
          final previous = _subjectOf(id, c);
          if (previous != null && previous.id != s.id) {
            final from = _boxes['$id|${previous.id}']!;
            final to = _boxes['$id|${s.id}']!;
            if (to.text.trim().isEmpty && from.text.trim().isNotEmpty) {
              to.text = from.text;
              from.text = '';
            }
          }
          (_choices[id] ??= {})[c.name] = s.id;
        }
      });
    } catch (e) {
      if (mounted) SdToast.show(context, resultErrorMessage(l10n, e));
    }
  }

  bool get _dirty => _boxes.entries.any((e) => e.value.text.trim().toUpperCase() != (_saved[e.key] ?? '').toUpperCase());

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final subjects = {for (final c in _columns) for (final s in c.subjects) s.id: s};
    final entries = <String, Map<String, MarkEntry?>>{};
    _errors.clear();
    for (final e in _boxes.entries) {
      final text = e.value.text.trim();
      if (text.toUpperCase() == (_saved[e.key] ?? '').toUpperCase()) continue;
      final [studentId, subjectId] = e.key.split('|');
      try {
        (entries[studentId] ??= {})[subjectId] = ResultRepository.parse(text, subjects[subjectId]!);
      } catch (err) {
        _errors[e.key] = resultErrorMessage(l10n, err);
      }
    }
    if (_errors.isNotEmpty) {
      setState(() {});
      final first = _errors.keys.first;
      final student = _roster.where((r) => first.startsWith(r.id)).firstOrNull;
      final subject = subjects[first.split('|').last];
      SdToast.show(context, '${student?.name ?? ''} · ${subject?.name ?? ''}: ${_errors[first]}');
      return;
    }
    setState(() => _saving = true);
    try {
      final n = await ref.read(resultRepositoryProvider).saveMarks(widget.examId, entries);
      for (final e in _boxes.entries) {
        _saved[e.key] = e.value.text.trim().toUpperCase();
        if (e.value.text != _saved[e.key]) e.value.text = _saved[e.key]!;
      }
      ref.read(resultsRevisionProvider.notifier).state++;
      if (mounted) SdToast.show(context, l10n.resMarksSaved(n));
    } catch (e) {
      if (mounted) SdToast.show(context, resultErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    final l10n = AppLocalizations.of(context);
    if (_dirty) {
      final ok = await SdDialog.confirm(
        context,
        title: l10n.resUnsavedTitle,
        message: l10n.resUnsavedBody,
        confirmLabel: l10n.resLeaveWithoutSaving,
        cancelLabel: l10n.cancel,
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    context.go('/results');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final academic = ref.watch(academicControllerProvider);
    final division = academic.divisions.where((d) => d.id == widget.divisionId).firstOrNull;
    final program = academic.programs.where((p) => p.id == division?.programId).firstOrNull;

    final header = Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: Row(children: [
        IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: _leave),
        const SizedBox(width: SdSpace.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.resEnterMarks, style: theme.textTheme.headlineSmall),
            Text(
              '${_exam?.name ?? ''} · ${program?.name ?? ''} ${division?.name ?? ''}',
              style: theme.textTheme.bodySmall,
            ),
          ]),
        ),
        SdButton(label: l10n.save, icon: Icons.check, onPressed: _saving || !_loaded ? null : _save),
      ]),
    );

    if (!_loaded) return SdPage(children: [header, const SdSkeleton(height: 300)]);
    if (_columns.isEmpty) {
      return SdPage(children: [
        header,
        SdEmptyState(
          icon: Icons.menu_book_outlined,
          title: l10n.resNoSubjects,
          message: l10n.resNoSubjectsHint,
          action: SdButton(label: l10n.resSetup, onPressed: () => context.go('/results/setup')),
        ),
      ]);
    }

    final column = _columns.firstWhere((c) => c.name == _column, orElse: () => _columns.first);
    return SdPage(children: [
      header,
      if (_exams.length > 1)
        Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
          for (final e in _exams)
            ChoiceChip(
              label: Text(e.name),
              selected: e.id == widget.examId,
              onSelected: (_) async {
                if (e.id == widget.examId) return;
                if (_dirty) {
                  final ok = await SdDialog.confirm(
                    context,
                    title: l10n.resUnsavedTitle,
                    message: l10n.resUnsavedBody,
                    confirmLabel: l10n.resLeaveWithoutSaving,
                    cancelLabel: l10n.cancel,
                    destructive: true,
                  );
                  if (!ok || !context.mounted) return;
                }
                context.go('/results/marks?exam=${e.id}&division=${widget.divisionId}');
              },
            ),
        ]),
      const SizedBox(height: SdSpace.md),
      Text(l10n.resChooseColumn, style: theme.textTheme.titleSmall),
      const SizedBox(height: SdSpace.sm),
      Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
        for (final c in _columns)
          ChoiceChip(
            label: Text(c.isGrade ? '${c.name} (${l10n.resGrade})' : c.name),
            selected: c.name == column.name,
            onSelected: (_) => setState(() => _column = c.name),
          ),
      ]),
      const SizedBox(height: SdSpace.md),
      Text(
        column.isGrade ? l10n.resEntryHintGrade : l10n.resEntryHintMarks(column.subjects.first.maxMarks),
        style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted),
      ),
      if (column.isChoice) ...[
        const SizedBox(height: SdSpace.sm),
        Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(l10n.resSetUnchosen, style: theme.textTheme.bodySmall),
          for (final s in column.subjects)
            ActionChip(
              label: Text(s.name),
              onPressed: () => _choose(
                [for (final st in _roster) if (_subjectOf(st.id, column) == null) st.id],
                column,
                s,
              ),
            ),
        ]),
      ],
      const SizedBox(height: SdSpace.md),
      SdCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < _roster.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Builder(builder: (context) {
              final st = _roster[i];
              final subject = _subjectOf(st.id, column);
              final key = subject == null ? null : '${st.id}|${subject.id}';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: SdSpace.xs),
                child: Row(children: [
                  SizedBox(width: 34, child: Text(st.roll?.toString() ?? '', style: theme.textTheme.bodySmall)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(st.name, style: theme.textTheme.bodyMedium),
                      if (column.isChoice)
                        PopupMenuButton<Subject>(
                          tooltip: l10n.resChangeSubject,
                          onSelected: (s) => _choose([st.id], column, s),
                          itemBuilder: (_) => [for (final s in column.subjects) PopupMenuItem(value: s, child: Text(s.name))],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              subject?.name ?? l10n.resChooseSubject,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: subject == null ? sd.leave : theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  SizedBox(
                    width: 84,
                    child: key == null
                        ? const SizedBox.shrink()
                        : TextField(
                            controller: _boxes[key],
                            textAlign: TextAlign.center,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) {
                              if (_errors.remove(key) != null) setState(() {});
                            },
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: column.isGrade ? 'A' : '0',
                              errorText: _errors[key] == null ? null : '!',
                            ),
                          ),
                  ),
                ]),
              );
            }),
          ],
        ]),
      ),
      const SizedBox(height: SdSpace.lg),
      SdButton(label: l10n.save, icon: Icons.check, expand: true, onPressed: _saving ? null : _save),
    ]);
  }
}
