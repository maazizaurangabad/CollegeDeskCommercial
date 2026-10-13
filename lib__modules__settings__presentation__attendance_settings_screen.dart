import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_models.dart';
import '../../attendance/presentation/attendance_labels.dart';
import 'settings_page_header.dart';

/// Attendance marks, edit window, weekly holiday and the holiday calendar.
class AttendanceSettingsScreen extends ConsumerWidget {
  const AttendanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final repo = ref.watch(attendanceRepositoryProvider);
    ref.watch(attendanceRevisionProvider);
    void changed() => ref.read(attendanceRevisionProvider.notifier).state++;
    String message(Object e) => attendanceErrorMessage(l10n, e);
    final codes = ref.watch(attendanceCodesProvider).valueOrNull ?? const <AttendanceCode>[];
    final days = weekdayShort(l10n);

    return SdPage(
      children: [
        SettingsPageHeader(title: l10n.settingsAttendance),
        SdSection(
          title: l10n.attendanceCodes,
          trailing: SdButton(
            label: l10n.attendanceCodeAdd,
            icon: Icons.add,
            variant: SdButtonVariant.text,
            onPressed: () async {
              final result = await showDialog<_CodeInput>(context: context, builder: (_) => const _CodeDialog());
              if (result == null || !context.mounted) return;
              if (await runWithFeedback(
                context,
                () => repo.addCode(code: result.code, label: result.label, colorValue: result.color, countsAs: result.countsAs),
                message,
              )) {
                changed();
              }
            },
          ),
          child: SdCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < codes.length; i++) ...[
                  if (i > 0) const Divider(indent: SdSpace.lg),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(codes[i].colorValue).withValues(alpha: 0.15),
                      child: Text(codes[i].code,
                          style: TextStyle(color: Color(codes[i].colorValue), fontWeight: FontWeight.w700)),
                    ),
                    title: Text(codes[i].label),
                    subtitle: Text('${l10n.attendanceCountsAs}: ${countsAsLabel(l10n, codes[i].countsAs)}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          final result = await showDialog<_CodeInput>(
                            context: context,
                            builder: (_) => _CodeDialog(existing: codes[i]),
                          );
                          if (result == null || !context.mounted) return;
                          if (await runWithFeedback(
                            context,
                            () => repo.updateCode(codes[i].id,
                                label: result.label, colorValue: result.color, countsAs: result.countsAs),
                            message,
                          )) {
                            changed();
                          }
                        } else if (await runWithFeedback(context, () => repo.deleteCode(codes[i].id), message)) {
                          changed();
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(l10n.rename)),
                        PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: SdSpace.xl),
        FutureBuilder<(int, List<int>)>(
          future: _windowAndWeeklyOff(repo),
          builder: (context, snapshot) {
            final (window, off) = snapshot.data ?? (7, const [DateTime.sunday]);
            return SdCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SdSelectField<int>(
                    label: l10n.attendanceEditWindow,
                    value: window,
                    options: [
                      (0, l10n.attendanceSameDayOnly),
                      for (final d in const [1, 3, 7, 15, 30]) (d, l10n.attendanceEditDays(d)),
                    ],
                    onChanged: (v) async {
                      await repo.setEditDays(v ?? window);
                      changed();
                    },
                  ),
                  Text(l10n.attendanceWeeklyOffTitle, style: theme.textTheme.bodySmall),
                  const SizedBox(height: SdSpace.sm),
                  Wrap(
                    spacing: SdSpace.sm,
                    runSpacing: SdSpace.sm,
                    children: [
                      for (var wd = 1; wd <= 7; wd++)
                        FilterChip(
                          label: Text(days[wd - 1]),
                          selected: off.contains(wd),
                          onSelected: (on) async {
                            final next = {...off};
                            if (on) {
                              next.add(wd);
                            } else {
                              next.remove(wd);
                            }
                            await repo.setWeeklyOff(next.toList()..sort());
                            changed();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: SdSpace.xl),
        SdSection(
          title: l10n.attendanceCalendar,
          trailing: SdButton(
            label: l10n.attendanceCalendarAdd,
            icon: Icons.add,
            variant: SdButtonVariant.text,
            onPressed: () async {
              final result = await showDialog<(DateTime, DayKind, String)>(context: context, builder: (_) => const _DayDialog());
              if (result == null || !context.mounted) return;
              if (await runWithFeedback(context, () => repo.setCalendarDay(result.$1, result.$2, result.$3), message)) {
                changed();
              }
            },
          ),
          child: FutureBuilder<List<CalendarEntry>>(
            future: repo.calendar(),
            builder: (context, snapshot) {
              final entries = snapshot.data ?? const <CalendarEntry>[];
              if (entries.isEmpty) return SdCard(child: Text(l10n.attendanceCalendarEmpty));
              final format = DateFormat('EEE, d MMM y');
              return SdCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < entries.length; i++) ...[
                      if (i > 0) const Divider(indent: SdSpace.lg),
                      ListTile(
                        leading: Icon(entries[i].kind == DayKind.exam ? Icons.edit_note : Icons.celebration_outlined),
                        title: Text(format.format(entries[i].date)),
                        subtitle: Text([
                          entries[i].kind == DayKind.exam ? l10n.attendanceExamDay : l10n.attendanceHoliday,
                          if (entries[i].note.isNotEmpty) entries[i].note,
                        ].join(' · ')),
                        trailing: IconButton(
                          tooltip: l10n.delete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await repo.removeCalendarDay(entries[i].id);
                            changed();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<(int, List<int>)> _windowAndWeeklyOff(AttendanceRepository repo) async =>
    (await repo.editDays(), await repo.weeklyOff());

class _CodeInput {
  const _CodeInput(this.code, this.label, this.color, this.countsAs);

  final String code;
  final String label;
  final int color;
  final CountsAs countsAs;
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({this.existing});

  final AttendanceCode? existing;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  static const _colors = [
    Color(0xFF2E7D32),
    Color(0xFFC62828),
    Color(0xFFB26A00),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFF455A64),
  ];

  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late Color _color = widget.existing == null ? _colors[3] : Color(widget.existing!.colorValue);
  late CountsAs _countsAs = widget.existing?.countsAs ?? CountsAs.absent;

  @override
  void dispose() {
    _code.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? l10n.attendanceCodeAdd : widget.existing!.code),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.existing == null)
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                maxLength: 3,
                decoration: InputDecoration(labelText: l10n.attendanceCodeLetter),
              ),
            TextField(controller: _label, decoration: InputDecoration(labelText: l10n.attendanceCodeLabel)),
            const SizedBox(height: SdSpace.lg),
            SdSelectField<CountsAs>(
              label: l10n.attendanceCountsAs,
              value: _countsAs,
              options: [for (final c in CountsAs.values) (c, countsAsLabel(l10n, c))],
              onChanged: (v) => setState(() => _countsAs = v ?? _countsAs),
            ),
            SdColorChoice(selected: _color, choices: _colors, onChanged: (c) => setState(() => _color = c)),
          ],
        ),
      ),
      actions: [
        SdButton(label: l10n.cancel, variant: SdButtonVariant.text, onPressed: () => Navigator.of(context).pop()),
        SdButton(
          label: l10n.save,
          onPressed: () => Navigator.of(context).pop(
            _CodeInput(widget.existing?.code ?? _code.text, _label.text, _color.toARGB32(), _countsAs),
          ),
        ),
      ],
    );
  }
}

class _DayDialog extends StatefulWidget {
  const _DayDialog();

  @override
  State<_DayDialog> createState() => _DayDialogState();
}

class _DayDialogState extends State<_DayDialog> {
  DateTime _date = DateTime.now();
  DayKind _kind = DayKind.holiday;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.attendanceCalendarAdd),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SdDateField(
            label: l10n.attendanceDate,
            value: _date,
            clearable: false,
            onChanged: (d) => setState(() => _date = d ?? _date),
          ),
          SdSelectField<DayKind>(
            label: l10n.attendanceDayType,
            value: _kind,
            options: [(DayKind.holiday, l10n.attendanceHoliday), (DayKind.exam, l10n.attendanceExamDay)],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          TextField(controller: _note, decoration: InputDecoration(labelText: l10n.attendanceNote)),
        ],
      ),
      actions: [
        SdButton(label: l10n.cancel, variant: SdButtonVariant.text, onPressed: () => Navigator.of(context).pop()),
        SdButton(label: l10n.save, onPressed: () => Navigator.of(context).pop((_date, _kind, _note.text))),
      ],
    );
  }
}
