import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/attendance_providers.dart';
import '../domain/attendance_models.dart';
import 'attendance_labels.dart';
import 'division_picker.dart';

/// One division, one month: every student's marks day by day, with totals.
class AttendanceRegisterScreen extends ConsumerStatefulWidget {
  const AttendanceRegisterScreen({super.key, this.initialDivisionId, this.backTo});

  /// Class to open with (e.g. from a student's profile).
  final String? initialDivisionId;

  /// Where the back button returns; the Attendance home when null.
  final String? backTo;

  @override
  ConsumerState<AttendanceRegisterScreen> createState() => _AttendanceRegisterScreenState();
}

class _AttendanceRegisterScreenState extends ConsumerState<AttendanceRegisterScreen> {
  String? _divisionId;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Future<MonthGrid>? _future;
  String? _key;

  @override
  void initState() {
    super.initState();
    _divisionId = widget.initialDivisionId;
  }

  Future<MonthGrid>? _load(int revision) {
    if (_divisionId == null) return null;
    final key = '$_divisionId|${_month.year}-${_month.month}|$revision';
    if (key != _key) {
      _key = key;
      _future = ref.read(attendanceRepositoryProvider).monthGrid(_divisionId!, _month.year, _month.month);
    }
    return _future;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final codes = {for (final c in ref.watch(attendanceCodesProvider).valueOrNull ?? const <AttendanceCode>[]) c.code: c};
    final future = _load(ref.watch(attendanceRevisionProvider));
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;

    return SdPage(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.back,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go(widget.backTo ?? '/attendance'),
            ),
            const SizedBox(width: SdSpace.xs),
            Expanded(child: Text(l10n.attendanceRegister, style: theme.textTheme.headlineSmall)),
          ],
        ),
        const SizedBox(height: SdSpace.lg),
        DivisionPicker(divisionId: _divisionId, onChanged: (id) => setState(() => _divisionId = id)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            ),
            Expanded(
              child: Text(DateFormat('MMMM y').format(_month), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: isCurrentMonth ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ],
        ),
        const SizedBox(height: SdSpace.md),
        if (future == null)
          SdEmptyState(icon: Icons.calendar_view_month_outlined, title: l10n.attendanceChooseDivision, message: '')
        else
          FutureBuilder<MonthGrid>(
            future: future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SdSkeleton(height: 240);
              final grid = snapshot.data!;
              if (grid.students.isEmpty) {
                return SdEmptyState(icon: Icons.people_outline, title: l10n.attendanceNoStudents, message: '');
              }
              const cell = 30.0;
              final cellStyle = theme.textTheme.labelMedium;
              Widget box(Widget child, {Color? fill, double width = cell}) => Container(
                    width: width,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: fill, border: Border(right: BorderSide(color: sd.border, width: 0.5))),
                    child: child,
                  );
              Color? shade(int day) => grid.dayKinds.containsKey(day) ? sd.subtleFill : null;
              return SdCard(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        box(Text('#', style: cellStyle), width: 40),
                        box(Align(alignment: Alignment.centerLeft, child: Text(l10n.fieldName, style: cellStyle)), width: 190),
                        for (var d = 1; d <= grid.daysInMonth; d++) box(Text('$d', style: cellStyle), fill: shade(d)),
                        box(Text(l10n.registerTotal, style: cellStyle), width: 64),
                        box(Text(l10n.registerPercent, style: cellStyle), width: 56),
                      ]),
                      for (final s in grid.students) ...[
                        Divider(height: 1, color: sd.border),
                        Row(children: [
                          box(Text(s.rollNumber?.toString() ?? '–', style: cellStyle), width: 40),
                          box(
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(s.fullName, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                            ),
                            width: 190,
                          ),
                          for (var d = 1; d <= grid.daysInMonth; d++)
                            box(
                              Text(
                                grid.marks[s.studentId]?[d] ?? '',
                                style: cellStyle?.copyWith(
                                  color: codes[grid.marks[s.studentId]?[d]] == null
                                      ? null
                                      : Color(codes[grid.marks[s.studentId]?[d]]!.colorValue),
                                ),
                              ),
                              fill: shade(d),
                            ),
                          box(
                            Text(
                              '${formatPercent(grid.totals[s.studentId]?.present)}/'
                              '${formatPercent((grid.totals[s.studentId]?.present ?? 0) + (grid.totals[s.studentId]?.absent ?? 0))}',
                              style: cellStyle,
                            ),
                            width: 64,
                          ),
                          Builder(builder: (context) {
                            final p = grid.totals[s.studentId]?.percent;
                            final low = p != null && p < 75;
                            return box(
                              Text(formatPercent(p), style: cellStyle?.copyWith(color: low ? sd.absent : null)),
                              width: 56,
                              fill: low ? sd.absent.withValues(alpha: 0.08) : null,
                            );
                          }),
                        ]),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: SdSpace.md),
        Wrap(
          spacing: SdSpace.md,
          runSpacing: SdSpace.xs,
          children: [
            for (final c in codes.values)
              Text('${c.code} = ${c.label}', style: theme.textTheme.bodySmall?.copyWith(color: Color(c.colorValue))),
            Text(l10n.registerLow, style: theme.textTheme.bodySmall?.copyWith(color: sd.absent)),
          ],
        ),
      ],
    );
  }
}
