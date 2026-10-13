import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/academic/academic_messages.dart';
import '../../../platform/academic/academic_models.dart';
import '../../../platform/workspace/institution_draft.dart';
import 'settings_page_header.dart';

class AcademicYearsScreen extends ConsumerWidget {
  const AcademicYearsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(academicControllerProvider);
    final controller = ref.read(academicControllerProvider.notifier);
    final format = DateFormat('d MMM y');
    final sd = SdColors.of(context);
    String message(Object e) => academicErrorMessage(l10n, e);

    return SdPage(
      children: [
        SettingsPageHeader(
          title: l10n.settingsAcademicYears,
          trailing: SdButton(
            label: l10n.yearsAdd,
            icon: Icons.add,
            onPressed: () async {
              final result = await showDialog<_YearInput>(context: context, builder: (_) => const _AddYearDialog());
              if (result == null || !context.mounted) return;
              await runWithFeedback(context, () => controller.addYear(result.label, result.start, result.end), message);
            },
          ),
        ),
        if (snapshot.years.isEmpty)
          SdEmptyState(icon: Icons.calendar_month_outlined, title: l10n.yearsEmpty, message: l10n.classesNoYear)
        else
          SdCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < snapshot.years.length; i++) ...[
                  if (i > 0) const Divider(indent: SdSpace.lg),
                  Builder(builder: (context) {
                    final year = snapshot.years[i];
                    final (statusText, statusColor) = switch (year.status) {
                      AcademicYearStatus.active => (l10n.yearActive, sd.present),
                      AcademicYearStatus.inactive => (l10n.yearInactive, sd.textMuted),
                      AcademicYearStatus.closed => (l10n.yearClosed, sd.textMuted),
                    };
                    return ListTile(
                      leading: Icon(year.isClosed ? Icons.lock_outline : Icons.calendar_month_outlined),
                      title: Text(year.label),
                      subtitle: Text(
                        '${l10n.yearDates(format.format(year.startDate), format.format(year.endDate))}\n$statusText',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: statusColor),
                      ),
                      isThreeLine: true,
                      trailing: year.isClosed
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (choice) async {
                                if (choice == 'active') {
                                  await runWithFeedback(context, () => controller.setActiveYear(year.id), message);
                                } else if (choice == 'close') {
                                  final ok = await SdDialog.confirm(
                                    context,
                                    title: l10n.yearCloseConfirmTitle(year.label),
                                    message: l10n.yearCloseConfirmMessage,
                                    confirmLabel: l10n.yearClose,
                                    cancelLabel: l10n.cancel,
                                    destructive: true,
                                  );
                                  if (ok && context.mounted) {
                                    await runWithFeedback(context, () => controller.closeYear(year.id), message);
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                if (!year.isActive) PopupMenuItem(value: 'active', child: Text(l10n.yearSetActive)),
                                PopupMenuItem(value: 'close', child: Text(l10n.yearClose)),
                              ],
                            ),
                    );
                  }),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _YearInput {
  const _YearInput(this.label, this.start, this.end);

  final String label;
  final DateTime start;
  final DateTime end;
}

class _AddYearDialog extends StatefulWidget {
  const _AddYearDialog();

  @override
  State<_AddYearDialog> createState() => _AddYearDialogState();
}

class _AddYearDialogState extends State<_AddYearDialog> {
  late final TextEditingController _label;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final year = InstitutionDraft.defaultYear(DateTime(now.year + 1, 6, 1));
    _label = TextEditingController(text: year.label);
    _start = year.start;
    _end = year.end;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final format = DateFormat('d MMM y');
    return AlertDialog(
      title: Text(l10n.yearsAdd),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _label, decoration: InputDecoration(labelText: l10n.fieldYearLabel)),
          const SizedBox(height: SdSpace.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.fieldYearStart),
            subtitle: Text(format.format(_start)),
            onTap: () => _pick(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.fieldYearEnd),
            subtitle: Text(format.format(_end)),
            onTap: () => _pick(false),
          ),
        ],
      ),
      actions: [
        SdButton(label: l10n.cancel, variant: SdButtonVariant.text, onPressed: () => Navigator.of(context).pop()),
        SdButton(
          label: l10n.save,
          onPressed: () => Navigator.of(context).pop(_YearInput(_label.text, _start, _end)),
        ),
      ],
    );
  }
}
