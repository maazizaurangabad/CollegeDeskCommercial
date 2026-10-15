import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../messages/application/messages_providers.dart';
import '../../messages/data/message_repository.dart';
import '../../messages/domain/message_models.dart';
import '../../students/presentation/student_labels.dart';
import '../application/fees_providers.dart';
import '../domain/fee_models.dart';

/// One family to remind: one mobile, one or more children with fees pending.
class _FeeFamily {
  _FeeFamily(this.mobile);

  final String? mobile;
  final List<StudentFeeBalance> students = [];
  DateTime? sentAt;

  int get balance => students.fold(0, (a, s) => a + s.balance);
  int get overdue => students.fold(0, (a, s) => a + s.overdue);
  String get names => students.map((s) => s.name).join(', ');
  String get key => mobile ?? students.first.studentId;
}

/// Fee reminders on WhatsApp: parents whose fees are overdue (or pending),
/// one tap each, with a tick once sent today.
class FeeRemindersScreen extends ConsumerStatefulWidget {
  const FeeRemindersScreen({super.key});

  @override
  ConsumerState<FeeRemindersScreen> createState() => _FeeRemindersScreenState();
}

class _FeeRemindersScreenState extends ConsumerState<FeeRemindersScreen> {
  bool _overdueOnly = true;
  String? _programId;
  final Set<String> _busy = {};
  late Future<(List<_FeeFamily>, MessageSettings)> _data = _load();

  Future<(List<_FeeFamily>, MessageSettings)> _load() async {
    final year = ref.read(academicControllerProvider).activeYear;
    final settings = await ref.read(messageRepositoryProvider).loadSettings();
    if (year == null) return (<_FeeFamily>[], settings);
    final all = await ref.read(feeRepositoryProvider).balances(year.id);
    final sent = await ref.read(messageRepositoryProvider).sentOn(DateTime.now(), {MessageKind.feeDue});
    final families = <String, _FeeFamily>{};
    for (final b in all) {
      if (_programId != null && b.programId != _programId) continue;
      if (_overdueOnly ? b.overdue <= 0 : b.balance <= 0) continue;
      final key = b.mobile ?? 'none:${b.studentId}';
      (families[key] ??= _FeeFamily(b.mobile)).students.add(b);
    }
    for (final f in families.values) {
      final times = f.students.map((s) => sent[s.studentId]).toList();
      f.sentAt = times.contains(null) ? null : times.whereType<DateTime>().reduce((a, b) => a.isAfter(b) ? a : b);
    }
    return (families.values.toList(), settings);
  }

  void _reload() => setState(() => _data = _load());

  String _body(_FeeFamily f, MessageSettings s) => MessageRepository.fillFeeBody(
        s.feeTemplate,
        names: [for (final st in f.students) st.name],
        classes: [for (final st in f.students) st.classLabel],
        balance: rupees(f.balance),
        overdue: rupees(f.overdue),
        date: DateTime.now(),
        institution: ref.read(activeOrganizationProvider).name,
      );

  Future<void> _send(_FeeFamily f, String body, {bool copy = false}) async {
    final l10n = AppLocalizations.of(context);
    final mobile = f.mobile;
    if (mobile == null) return;
    if (f.sentAt != null && !copy) {
      final again = await SdDialog.confirm(
        context,
        title: l10n.msgSendAgainTitle,
        message: l10n.feeReminderAgain,
        confirmLabel: l10n.msgSendAgain,
        cancelLabel: l10n.cancel,
      );
      if (!again || !mounted) return;
    }
    setState(() => _busy.add(f.key));
    try {
      if (copy) {
        await copyText(body);
      } else if (!await openWhatsApp(mobile: mobile, text: body)) {
        if (mounted) SdToast.show(context, l10n.msgOpenFailed);
        return;
      }
      await ref.read(messageRepositoryProvider).recordFeeReminder(
            students: [for (final s in f.students) (s.studentId, s.name, s.classLabel)],
            mobile: mobile,
            body: body,
            date: DateTime.now(),
            channel: copy ? 'copy' : 'whatsapp',
          );
      if (!mounted) return;
      ref.read(messagesRevisionProvider.notifier).state++;
      if (copy) SdToast.show(context, l10n.msgCopied);
      _reload();
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy.remove(f.key));
    }
  }

  Future<void> _preview(_FeeFamily f, String body) async {
    final l10n = AppLocalizations.of(context);
    final result = await SdSheet.show<(String, String)>(
      context,
      title: f.names,
      builder: (_) => _EditSheet(text: body, subtitle: f.mobile ?? '', sendLabel: l10n.msgSend, copyLabel: l10n.msgCopy),
    );
    if (result == null || !mounted) return;
    final text = result.$2.trim().isEmpty ? body : result.$2.trim();
    await _send(f, text, copy: result.$1 == 'copy');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final academic = ref.watch(academicControllerProvider);

    return SdPage(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: SdSpace.lg),
        child: Row(children: [
          IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/fees')),
          const SizedBox(width: SdSpace.xs),
          Expanded(child: Text(l10n.feeReminders, style: theme.textTheme.headlineSmall)),
          SdButton(
            label: l10n.msgTemplatesButton,
            icon: Icons.edit_note_outlined,
            variant: SdButtonVariant.text,
            onPressed: () => context.go('/messages/templates?from=messages'),
          ),
        ]),
      ),
      Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
        ChoiceChip(
          label: Text(l10n.feeOverdueOnly),
          selected: _overdueOnly,
          onSelected: (_) {
            _overdueOnly = true;
            _reload();
          },
        ),
        ChoiceChip(
          label: Text(l10n.feeAnyBalance),
          selected: !_overdueOnly,
          onSelected: (_) {
            _overdueOnly = false;
            _reload();
          },
        ),
      ]),
      const SizedBox(height: SdSpace.md),
      SdSelectField<String>(
        label: l10n.fieldClass,
        value: _programId,
        clearLabel: l10n.studentsFilterAll,
        emptyText: l10n.studentsFilterAll,
        options: [for (final p in academic.programs) (p.id, p.name)],
        onChanged: (v) {
          _programId = v;
          _reload();
        },
      ),
      const SizedBox(height: SdSpace.lg),
      FutureBuilder<(List<_FeeFamily>, MessageSettings)>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(l10n.saveFailed);
          if (!snapshot.hasData) return const SdSkeleton(height: 200);
          final (families, settings) = snapshot.data!;
          if (families.isEmpty) {
            return SdEmptyState(icon: Icons.verified_outlined, title: l10n.feeNothingPending, message: '');
          }
          final withNumber = families.where((f) => f.mobile != null).toList();
          final noNumber = families.where((f) => f.mobile == null).toList();
          final sent = withNumber.where((f) => f.sentAt != null).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (withNumber.isNotEmpty)
              SdSection(
                title: l10n.msgParentsTitle(withNumber.length),
                trailing: StatusPill(
                  text: l10n.msgProgress(sent, withNumber.length),
                  color: sent == withNumber.length ? sd.present : sd.info,
                ),
                child: SdCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < withNumber.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      Builder(builder: (context) {
                        final f = withNumber[i];
                        final body = _body(f, settings);
                        return ListTile(
                          onTap: () => _preview(f, body),
                          leading: Icon(
                            f.sentAt != null ? Icons.check_circle : Icons.chat_outlined,
                            color: f.sentAt != null ? sd.present : sd.textMuted,
                          ),
                          title: Text(f.names),
                          subtitle: Text([
                            f.students.map((s) => s.classLabel).toSet().join(' / '),
                            f.mobile ?? '',
                            '${l10n.feeBalance} ${rupees(f.balance)}',
                            if (f.overdue > 0) '${l10n.feeOverdue} ${rupees(f.overdue)}',
                            if (f.sentAt != null) l10n.msgSentAt(DateFormat('h:mm a').format(f.sentAt!.toLocal())),
                          ].where((t) => t.isNotEmpty).join(' · ')),
                          trailing: _busy.contains(f.key)
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : (f.sentAt != null
                                  ? IconButton(tooltip: l10n.msgSendAgain, icon: const Icon(Icons.refresh), onPressed: () => _send(f, body))
                                  : IconButton.filled(tooltip: l10n.msgSend, icon: const Icon(Icons.send), onPressed: () => _send(f, body))),
                        );
                      }),
                    ],
                  ]),
                ),
              ),
            if (noNumber.isNotEmpty) ...[
              const SizedBox(height: SdSpace.xxl),
              SdSection(
                title: l10n.msgNoNumberTitle(noNumber.length),
                child: SdCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final f in noNumber)
                      ListTile(
                        leading: Icon(Icons.phone_disabled_outlined, color: sd.leave),
                        title: Text(f.names),
                        subtitle: Text('${f.students.first.classLabel} · ${l10n.feeBalance} ${rupees(f.balance)}'),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => context.go('/students/${f.students.first.studentId}/edit'),
                      ),
                  ]),
                ),
              ),
            ],
          ]);
        },
      ),
    ]);
  }
}

/// Editable message text with Copy and WhatsApp. Pops ('send' | 'copy', text).
class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.text, required this.subtitle, required this.sendLabel, required this.copyLabel});

  final String text;
  final String subtitle;
  final String sendLabel;
  final String copyLabel;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _c = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: SdSpace.md),
          TextField(controller: _c, minLines: 4, maxLines: 12),
          const SizedBox(height: SdSpace.lg),
          Wrap(spacing: SdSpace.sm, alignment: WrapAlignment.end, children: [
            SdButton(
              label: widget.copyLabel,
              icon: Icons.copy_outlined,
              variant: SdButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(('copy', _c.text)),
            ),
            SdButton(
              label: widget.sendLabel,
              icon: Icons.send_outlined,
              onPressed: () => Navigator.of(context).pop(('send', _c.text)),
            ),
          ]),
        ]),
      ),
    );
  }
}
