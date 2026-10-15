import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/academic/academic_models.dart';
import '../application/students_providers.dart';
import '../domain/student_models.dart';
import 'student_labels.dart';

/// How a list of students is ordered.
enum StudentSort { roll, gr, name, code }

/// Compares GR numbers, codes and the like so that 9 comes before 10.
int compareNatural(String? a, String? b) {
  final x = (a ?? '').trim(), y = (b ?? '').trim();
  if (x.isEmpty || y.isEmpty) return x.isEmpty ? (y.isEmpty ? 0 : 1) : -1;
  final nx = int.tryParse(x), ny = int.tryParse(y);
  if (nx != null && ny != null) return nx.compareTo(ny);
  final mx = RegExp(r'^(\D*)(\d+)(.*)$').firstMatch(x), my = RegExp(r'^(\D*)(\d+)(.*)$').firstMatch(y);
  if (mx != null && my != null && mx.group(1)!.toLowerCase() == my.group(1)!.toLowerCase()) {
    final c = int.parse(mx.group(2)!).compareTo(int.parse(my.group(2)!));
    if (c != 0) return c;
  }
  return x.toLowerCase().compareTo(y.toLowerCase());
}

/// Sorts students; ties fall back to roll number, then name.
List<StudentListItem> sortStudents(List<StudentListItem> items, StudentSort sort) {
  int byRoll(StudentListItem a, StudentListItem b) => (a.rollNumber ?? 1 << 20).compareTo(b.rollNumber ?? 1 << 20);
  int byName(StudentListItem a, StudentListItem b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
  return [...items]..sort((a, b) {
      final c = switch (sort) {
        StudentSort.roll => byRoll(a, b),
        StudentSort.gr => compareNatural(a.grNumber, b.grNumber),
        StudentSort.name => byName(a, b),
        StudentSort.code => compareNatural(a.displayCode, b.displayCode),
      };
      if (c != 0) return c;
      final r = byRoll(a, b);
      return r != 0 ? r : byName(a, b);
    });
}

String studentSortLabel(AppLocalizations l10n, StudentSort s) => switch (s) {
      StudentSort.roll => l10n.sortRoll,
      StudentSort.gr => l10n.sortGr,
      StudentSort.name => l10n.sortName,
      StudentSort.code => l10n.sortCode,
    };

/// Choose a student: pick a class to see its students straight away (in
/// roll order, or another order), or type a name, GR or code.
class StudentPicker extends ConsumerStatefulWidget {
  const StudentPicker({super.key, required this.onPicked, this.enabled = true, this.searchHint});

  final ValueChanged<StudentListItem> onPicked;
  final bool enabled;
  final String? searchHint;

  @override
  ConsumerState<StudentPicker> createState() => _StudentPickerState();
}

class _StudentPickerState extends ConsumerState<StudentPicker> {
  String _query = '';
  String? _programId;
  String? _divisionId;
  StudentSort _sort = StudentSort.roll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final academic = ref.watch(academicControllerProvider);
    final year = academic.activeYear;
    final List<Division> divisions = _programId == null ? const [] : academic.divisionsOf(_programId!);
    final byClass = _programId != null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SdTextField(
        hint: widget.searchHint ?? l10n.feeFindStudent,
        prefixIcon: Icons.search,
        onChanged: (v) => setState(() => _query = v.trim()),
      ),
      const SizedBox(height: SdSpace.md),
      Row(children: [
        Expanded(
          child: SdSelectField<String>(
            label: l10n.studentsFilterClass,
            value: _programId,
            clearLabel: l10n.studentsFilterAll,
            emptyText: l10n.studentsFilterAll,
            options: [for (final p in academic.programs) (p.id, p.name)],
            onChanged: (v) => setState(() {
              _programId = v;
              _divisionId = null;
            }),
          ),
        ),
        if (byClass && divisions.length > 1) ...[
          const SizedBox(width: SdSpace.sm),
          Expanded(
            child: SdSelectField<String>(
              label: l10n.studentsFilterDivision,
              value: _divisionId,
              clearLabel: l10n.studentsFilterAll,
              emptyText: l10n.studentsFilterAll,
              options: [for (final d in divisions) (d.id, d.name)],
              onChanged: (v) => setState(() => _divisionId = v),
            ),
          ),
        ],
      ]),
      if (byClass) ...[
        const SizedBox(height: SdSpace.sm),
        Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
          for (final s in StudentSort.values)
            ChoiceChip(label: Text(studentSortLabel(l10n, s)), selected: _sort == s, onSelected: (_) => setState(() => _sort = s)),
        ]),
      ],
      const SizedBox(height: SdSpace.md),
      if (!byClass && _query.length < 2)
        Text(l10n.pickerHint, style: theme.textTheme.bodySmall)
      else
        FutureBuilder<List<StudentListItem>>(
          future: ref.read(studentRepositoryProvider).list(
                query: byClass ? '' : _query,
                academicYearId: year?.id,
                limit: byClass ? 50000 : 30,
              ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SdSkeleton(height: 120);
            var items = snapshot.data!;
            if (byClass) {
              final allowed = _divisionId != null ? {_divisionId} : divisions.map((d) => d.id).toSet();
              final q = _query.toLowerCase();
              items = items
                  .where((s) => allowed.contains(s.divisionId))
                  .where((s) =>
                      q.isEmpty || '${s.fullName} ${s.grNumber ?? ''} ${s.displayCode}'.toLowerCase().contains(q))
                  .toList();
              items = sortStudents(items, _sort);
            }
            if (items.isEmpty) return Text(l10n.studentsNoMatch, style: theme.textTheme.bodySmall);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l10n.studentsCount(items.length), style: theme.textTheme.bodySmall),
              const SizedBox(height: SdSpace.xs),
              SdCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 32,
                        child: Text(items[i].rollNumber?.toString() ?? '', style: theme.textTheme.bodySmall),
                      ),
                      title: Text(items[i].fullName),
                      subtitle: Text([
                        if ((items[i].grNumber ?? '').isNotEmpty) '${l10n.idGr} ${items[i].grNumber}',
                        items[i].displayCode,
                        placementName(academic, items[i].divisionId) ?? '',
                      ].where((x) => x.isNotEmpty).join(' · ')),
                      trailing: items[i].status == StudentStatus.active
                          ? const Icon(Icons.chevron_right)
                          : StatusPill(
                              text: studentStatusLabel(l10n, items[i].status),
                              color: SdColors.of(context).textMuted,
                            ),
                      onTap: widget.enabled ? () => widget.onPicked(items[i]) : null,
                    ),
                  ],
                ]),
              ),
            ]);
          },
        ),
    ]);
  }
}
