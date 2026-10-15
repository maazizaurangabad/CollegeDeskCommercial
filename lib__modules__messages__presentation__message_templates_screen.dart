import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../attendance/domain/attendance_models.dart';
import '../application/messages_providers.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';

/// Settings > Message templates: the texts parents receive, from how many
/// days the "days in a row" text is used, and which marks get a message.
class MessageTemplatesScreen extends ConsumerStatefulWidget {
  const MessageTemplatesScreen({super.key, this.backTo = '/settings'});

  /// Where the back arrow goes (Settings or Messages).
  final String backTo;

  @override
  ConsumerState<MessageTemplatesScreen> createState() => _MessageTemplatesScreenState();
}

class _MessageTemplatesScreenState extends ConsumerState<MessageTemplatesScreen> {
  final _absent = TextEditingController();
  final _streak = TextEditingController();
  final _fee = TextEditingController();
  int _days = MessageSettings.defaultStreakDays;
  Set<String> _codes = {};
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _absent.addListener(_refresh);
    _streak.addListener(_refresh);
    _fee.addListener(_refresh);
    _reload();
  }

  void _refresh() => setState(() {});

  Future<void> _reload() async {
    final s = await ref.read(messageRepositoryProvider).loadSettings();
    if (!mounted) return;
    _absent.text = s.absentTemplate;
    _streak.text = s.streakTemplate;
    _fee.text = s.feeTemplate;
    setState(() {
      _days = s.streakDays;
      _codes = {...s.codes};
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _absent.dispose();
    _streak.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_codes.isEmpty) {
      SdToast.show(context, l10n.msgCodesEmpty);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(messageRepositoryProvider).saveSettings(MessageSettings(
            absentTemplate: _absent.text.trim().isEmpty ? MessageSettings.defaultAbsentTemplate : _absent.text,
            streakTemplate: _streak.text.trim().isEmpty ? MessageSettings.defaultStreakTemplate : _streak.text,
            streakDays: _days,
            codes: _codes,
            feeTemplate: _fee.text.trim().isEmpty ? MessageSettings.defaultFeeTemplate : _fee.text,
          ));
      ref.read(messagesRevisionProvider.notifier).state++;
      if (mounted) SdToast.show(context, l10n.msgTemplatesSaved);
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final ok = await SdDialog.confirm(
      context,
      title: l10n.msgResetTemplates,
      message: l10n.msgResetBody,
      confirmLabel: l10n.msgResetTemplates,
      cancelLabel: l10n.cancel,
    );
    if (!ok) return;
    await ref.read(messageRepositoryProvider).resetTemplates();
    ref.read(messagesRevisionProvider.notifier).state++;
    await _reload();
  }

  void _insert(TextEditingController c, String word) {
    final sel = c.selection;
    final text = c.text;
    final at = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    c.value = TextEditingValue(
      text: text.replaceRange(at, end, word),
      selection: TextSelection.collapsed(offset: at + word.length),
    );
  }

  String _feeExample(String template) => MessageRepository.fillFeeBody(
        template,
        names: const ['Ayaan Shaikh'],
        classes: const ['11th Science A'],
        balance: '₹2,500',
        overdue: '₹1,500',
        date: DateTime.now(),
        institution: ref.read(activeOrganizationProvider).name,
      );

  String _example(String template) {
    final sample = [
      const AbsentStudent(
        studentId: 'sample',
        fullName: 'Ayaan Shaikh',
        className: '11th Science A',
        divisionId: '',
        code: 'A',
        streak: 1,
        rollNumber: 7,
      ),
    ];
    return MessageRepository.fillBody(
      template,
      sample,
      date: DateTime.now(),
      days: _days,
      institution: ref.read(activeOrganizationProvider).name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final codes = (ref.watch(attendanceCodesProvider).valueOrNull ?? const <AttendanceCode>[])
        .where((c) => c.countsAs == CountsAs.absent)
        .toList();
    final words = <String, String>{
      MessagePlaceholders.student: l10n.msgPhStudent,
      MessagePlaceholders.className: l10n.msgPhClass,
      MessagePlaceholders.roll: l10n.msgPhRoll,
      MessagePlaceholders.date: l10n.msgPhDate,
      MessagePlaceholders.days: l10n.msgPhDays,
      MessagePlaceholders.institution: l10n.msgPhInstitution,
      MessagePlaceholders.mark: l10n.msgPhMark,
    };

    final feeWords = <String, String>{
      MessagePlaceholders.student: l10n.msgPhStudent,
      MessagePlaceholders.className: l10n.msgPhClass,
      MessagePlaceholders.balance: l10n.msgPhBalance,
      MessagePlaceholders.overdue: l10n.msgPhOverdue,
      MessagePlaceholders.date: l10n.msgPhDate,
      MessagePlaceholders.institution: l10n.msgPhInstitution,
    };

    Widget template(
      String title,
      TextEditingController c, {
      Map<String, String>? chips,
      String Function(String)? example,
    }) =>
        SdSection(
          title: title,
          child: SdCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: c, minLines: 4, maxLines: 10, keyboardType: TextInputType.multiline),
              const SizedBox(height: SdSpace.md),
              Wrap(spacing: SdSpace.xs, runSpacing: SdSpace.xs, children: [
                for (final e in (chips ?? words).entries)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(e.value),
                    tooltip: e.key,
                    onPressed: () => _insert(c, e.key),
                  ),
              ]),
              const SizedBox(height: SdSpace.md),
              Text(l10n.msgPreview, style: theme.textTheme.labelLarge),
              const SizedBox(height: SdSpace.xs),
              Container(
                padding: const EdgeInsets.all(SdSpace.md),
                decoration: BoxDecoration(color: sd.subtleFill, borderRadius: BorderRadius.circular(SdRadius.sm)),
                child: Text((example ?? _example)(c.text), style: theme.textTheme.bodyMedium),
              ),
            ]),
          ),
        );

    return SdPage(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: SdSpace.lg),
          child: Row(children: [
            IconButton(
              tooltip: l10n.back,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go(widget.backTo),
            ),
            const SizedBox(width: SdSpace.xs),
            Expanded(child: Text(l10n.settingsMessages, style: theme.textTheme.headlineSmall)),
          ]),
        ),
        if (!_loaded)
          const SdSkeleton(height: 240)
        else ...[
          Text(l10n.msgTemplatesHint, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
          const SizedBox(height: SdSpace.xl),
          template(l10n.msgTemplateAbsent, _absent),
          const SizedBox(height: SdSpace.xl),
          template(l10n.msgTemplateStreak, _streak),
          const SizedBox(height: SdSpace.md),
          Row(children: [
            Expanded(child: Text(l10n.msgStreakDaysLabel, style: theme.textTheme.bodyMedium)),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: _days <= 2 ? null : () => setState(() => _days--),
            ),
            Text('$_days', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _days >= 30 ? null : () => setState(() => _days++),
            ),
          ]),
          const SizedBox(height: SdSpace.xl),
          template(l10n.msgTemplateFee, _fee, chips: feeWords, example: _feeExample),
          const SizedBox(height: SdSpace.xl),
          SdSection(
            title: l10n.msgCodesTitle,
            child: SdCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l10n.msgCodesHint, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
                const SizedBox(height: SdSpace.md),
                Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
                  for (final c in codes)
                    FilterChip(
                      label: Text('${c.code} – ${c.label}'),
                      selected: _codes.contains(c.code),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _codes.add(c.code);
                        } else {
                          _codes.remove(c.code);
                        }
                      }),
                    ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: SdSpace.xl),
          Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, alignment: WrapAlignment.end, children: [
            SdButton(label: l10n.msgResetTemplates, variant: SdButtonVariant.text, onPressed: _saving ? null : _reset),
            SdButton(label: l10n.save, icon: Icons.check, onPressed: _saving ? null : _save),
          ]),
        ],
      ],
    );
  }
}
