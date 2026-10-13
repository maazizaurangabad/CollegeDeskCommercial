import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/data/data_providers.dart';
import '../../students/presentation/student_labels.dart';
import '../application/attendance_providers.dart';
import '../domain/attendance_models.dart';
import 'attendance_labels.dart';
import 'division_picker.dart';

/// Daily marking: choose a division and date; everyone starts present;
/// tap the absent students; save.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  static const _lastDivisionKey = 'attendance.last_division';

  String? _divisionId;
  DateTime _date = DateTime.now();
  AttendanceSheet? _sheet;
  Map<String, String> _marks = {};
  bool _dirty = false;
  bool _loading = false;
  bool _saving = false;
  bool _overrideHoliday = false;

  @override
  void initState() {
    super.initState();
    ref.read(appSettingsRepositoryProvider).getValue(_lastDivisionKey).then((id) {
      if (id != null && mounted) _open(id, _date);
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final l10n = AppLocalizations.of(context);
    return SdDialog.confirm(
      context,
      title: l10n.attendanceUnsaved,
      message: '',
      confirmLabel: l10n.attendanceDiscard,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
  }

  Future<void> _open(String? divisionId, DateTime date) async {
    if (!await _confirmDiscard()) return;
    setState(() {
      _divisionId = divisionId;
      _date = date;
      _sheet = null;
      _dirty = false;
      _overrideHoliday = false;
      _loading = divisionId != null;
    });
    if (divisionId == null) return;
    await ref.read(appSettingsRepositoryProvider).setValue(_lastDivisionKey, divisionId);
    final sheet = await ref.read(attendanceRepositoryProvider).sheet(divisionId, date);
    final codes = await ref.read(attendanceCodesProvider.future);
    if (!mounted || divisionId != _divisionId) return;
    final present = codes.firstWhere((c) => c.countsAs == CountsAs.present, orElse: () => codes.first).code;
    setState(() {
      _sheet = sheet;
      _marks = sheet.isSaved
          ? {for (final r in sheet.roster) r.studentId: sheet.marks[r.studentId] ?? present}
          : {for (final r in sheet.roster) r.studentId: present};
      _loading = false;
    });
  }

  bool get _editable {
    final s = _sheet;
    if (s == null) return false;
    return !s.day.isFuture && !s.day.isLocked && (s.day.isMarkable || _overrideHoliday);
  }

  void _cycle(String studentId, List<AttendanceCode> codes) {
    if (!_editable) return;
    final index = codes.indexWhere((c) => c.code == _marks[studentId]);
    setState(() {
      _marks[studentId] = codes[(index + 1) % codes.length].code;
      _dirty = true;
    });
  }

  Future<void> _choose(String studentId, List<AttendanceCode> codes) async {
    if (!_editable) return;
    final l10n = AppLocalizations.of(context);
    final picked = await SdSheet.show<String>(
      context,
      title: l10n.attendanceChooseMark,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in codes)
            ListTile(
              leading: _CodeChip(code: c.code, color: Color(c.colorValue)),
              title: Text(c.label),
              onTap: () => Navigator.of(sheet).pop(c.code),
            ),
        ],
      ),
    );
    if (picked != null) {
      setState(() {
        _marks[studentId] = picked;
        _dirty = true;
      });
    }
  }

  void _allPresent(List<AttendanceCode> codes) {
    final present = codes.firstWhere((c) => c.countsAs == CountsAs.present, orElse: () => codes.first).code;
    setState(() {
      _marks = {for (final k in _marks.keys) k: present};
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(attendanceRepositoryProvider).save(_divisionId!, _date, _marks, allowNonWorkingDay: _overrideHoliday);
      ref.read(attendanceRevisionProvider.notifier).state++;
      _dirty = false;
      if (mounted) SdToast.show(context, l10n.attendanceSaved);
      await _open(_divisionId, _date);
    } catch (e) {
      if (mounted) SdToast.show(context, attendanceErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final codes = ref.watch(attendanceCodesProvider).valueOrNull ?? const <AttendanceCode>[];
    final codeMap = {for (final c in codes) c.code: c};
    final mediaDir = ref.watch(startupStateProvider).mediaDir;
    final today = DateTime.now();
    final isToday = DateUtils.isSameDay(_date, today);
    final sheet = _sheet;
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < SdBreakpoints.compact ? SdSpace.lg : SdSpace.xl;
    final counts = <String, int>{};
    for (final m in _marks.values) {
      counts[m] = (counts[m] ?? 0) + 1;
    }

    final header = <Widget>[
      Row(
        children: [
          Expanded(child: Text(l10n.attendanceTitle, style: theme.textTheme.headlineSmall)),
          SdButton(
            label: l10n.attendanceRegister,
            icon: Icons.calendar_view_month_outlined,
            variant: SdButtonVariant.secondary,
            onPressed: () => context.go('/attendance/register'),
          ),
        ],
      ),
      const SizedBox(height: SdSpace.lg),
      DivisionPicker(divisionId: _divisionId, onChanged: (id) => _open(id, _date)),
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _open(_divisionId, _date.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(SdRadius.sm),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: today,
                );
                if (picked != null) await _open(_divisionId, picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: SdSpace.sm),
                child: Text(
                  isToday ? '${l10n.attendanceToday}, ${DateFormat('d MMM y').format(_date)}' : DateFormat('EEEE, d MMM y').format(_date),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isToday ? null : () => _open(_divisionId, _date.add(const Duration(days: 1))),
          ),
        ],
      ),
      if (sheet != null) ...[
        const SizedBox(height: SdSpace.sm),
        _banner(l10n, sheet, sd),
      ],
      const SizedBox(height: SdSpace.md),
    ];

    Widget body;
    if (_divisionId == null) {
      body = SdEmptyState(icon: Icons.fact_check_outlined, title: l10n.attendanceChooseDivision, message: '');
    } else if (_loading || sheet == null || codes.isEmpty) {
      body = Column(children: [for (var i = 0; i < 6; i++) const Padding(padding: EdgeInsets.only(bottom: SdSpace.md), child: SdSkeleton(height: 48))]);
    } else if (sheet.roster.isEmpty) {
      body = SdEmptyState(icon: Icons.people_outline, title: l10n.attendanceNoStudents, message: '');
    } else {
      body = SdCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < sheet.roster.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              Builder(builder: (context) {
                final r = sheet.roster[i];
                final code = codeMap[_marks[r.studentId]];
                return ListTile(
                  onTap: () => _cycle(r.studentId, codes),
                  onLongPress: () => _choose(r.studentId, codes),
                  leading: SizedBox(
                    width: 36,
                    child: Text(r.rollNumber?.toString() ?? '–', textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
                  ),
                  title: Row(
                    children: [
                      StudentAvatar(name: r.fullName, photo: studentPhoto(mediaDir, r.photoFileName), size: 32),
                      const SizedBox(width: SdSpace.md),
                      Expanded(child: Text(r.fullName, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  trailing: code == null
                      ? const SizedBox(width: 44)
                      : _CodeChip(code: code.code, color: Color(code.colorValue), large: true),
                );
              }),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, SdSpace.lg),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...header,
                      if (_editable && sheet != null && sheet.roster.isNotEmpty) ...[
                        Row(
                          children: [
                            Expanded(child: Text(l10n.attendanceTapHint, style: theme.textTheme.bodySmall)),
                            SdButton(
                              label: l10n.attendanceAllPresent,
                              variant: SdButtonVariant.text,
                              onPressed: () => _allPresent(codes),
                            ),
                          ],
                        ),
                        const SizedBox(height: SdSpace.sm),
                      ],
                      body,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (sheet != null && sheet.roster.isNotEmpty)
          Material(
            color: theme.colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: sd.border))),
                padding: EdgeInsets.symmetric(horizontal: pad, vertical: SdSpace.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: SdSpace.md,
                        runSpacing: SdSpace.xs,
                        children: [
                          for (final c in codes)
                            if ((counts[c.code] ?? 0) > 0)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                _CodeChip(code: c.code, color: Color(c.colorValue)),
                                const SizedBox(width: SdSpace.xs),
                                Text('${counts[c.code]}', style: theme.textTheme.titleSmall),
                              ]),
                        ],
                      ),
                    ),
                    if (_editable)
                      SdButton(
                        label: l10n.attendanceSave,
                        icon: Icons.check,
                        onPressed: _saving || (!_dirty && sheet.isSaved) ? null : _save,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _banner(AppLocalizations l10n, AttendanceSheet sheet, SdColors sd) {
    final day = sheet.day;
    String text;
    Color color = sd.info;
    Widget? action;
    if (day.isFuture) {
      text = l10n.attendanceFuture;
      color = sd.textMuted;
    } else if (!day.isMarkable && !_overrideHoliday) {
      text = day.kind == DayKind.weeklyOff
          ? l10n.attendanceWeeklyOff
          : '${l10n.attendanceHoliday}${day.note == null || day.note!.isEmpty ? '' : ': ${day.note}'}';
      color = sd.leave;
      if (!day.isLocked) {
        action = SdButton(
          label: l10n.attendanceMarkAnyway,
          variant: SdButtonVariant.text,
          onPressed: () => setState(() => _overrideHoliday = true),
        );
      }
    } else if (day.isLocked) {
      text = l10n.attendanceLocked;
      color = sd.textMuted;
    } else if (sheet.isSaved) {
      text = l10n.attendanceSavedAt(DateFormat('d MMM, h:mm a').format(sheet.savedAt!.toLocal()));
      color = sd.present;
    } else {
      text = day.kind == DayKind.exam ? '${l10n.attendanceExamDay}. ${l10n.attendanceNotMarked}' : l10n.attendanceNotMarked;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: SdSpace.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(SdRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color))),
          if (action != null) action,
        ],
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code, required this.color, this.large = false});

  final String code;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 40.0 : 26.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(SdRadius.sm),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(code, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: large ? 15 : 12)),
    );
  }
}
