import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../../platform/reporting/report_output.dart';
import '../../reports/application/reports_providers.dart';
import '../../students/presentation/student_labels.dart';
import '../application/messages_providers.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';

enum _Tab { send, history }

enum _Period { today, month, all }

/// Messages to parents: the day summary for staff, one tap per absent
/// student's parent, and the history of what was sent.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  _Tab _tab = _Tab.send;
  DateTime _date = _today();
  _Period _period = _Period.month;
  String _query = '';
  final Set<String> _busy = {};
  bool _exporting = false;
  String? _appliedQuery;

  Future<List<AbsentFamily>>? _families;
  Future<DaySummary>? _summary;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "/messages?date=2026-10-14" (from attendance) or "?tab=history".
    final params = GoRouterState.of(context).uri.queryParameters;
    final key = '${params['date']}|${params['tab']}';
    if (key != _appliedQuery) {
      _appliedQuery = key;
      final asked = DateTime.tryParse(params['date'] ?? '');
      if (asked != null) _date = DateTime(asked.year, asked.month, asked.day);
      if (params['tab'] == 'history') _tab = _Tab.history;
      _load(notify: false);
    }
  }

  void _load({bool notify = true}) {
    final academic = ref.read(academicControllerProvider);
    final divisions = orderedDivisions(academic);
    final labels = {for (final (id, label) in divisions) id: label};
    final repo = ref.read(messageRepositoryProvider);
    _families = repo.absentFamilies(
      _date,
      institution: ref.read(activeOrganizationProvider).name,
      divisionLabels: labels,
    );
    _summary = repo.daySummary(_date, divisions: divisions);
    if (notify && mounted) setState(() {});
  }

  void _setDate(DateTime d) {
    _date = DateTime(d.year, d.month, d.day);
    _load();
  }

  void _changed() {
    if (!mounted) return;
    ref.read(messagesRevisionProvider.notifier).state++;
    _load();
  }

  // ------------------------------------------------------------------ send

  Future<void> _send(AbsentFamily family, {String? text}) async {
    final l10n = AppLocalizations.of(context);
    if (family.mobile == null) return;
    if (family.isSent) {
      final again = await SdDialog.confirm(
        context,
        title: l10n.msgSendAgainTitle,
        message: l10n.msgSendAgainBody,
        confirmLabel: l10n.msgSendAgain,
        cancelLabel: l10n.cancel,
      );
      if (!again) return;
    }
    setState(() => _busy.add(family.key));
    try {
      final body = text ?? family.body;
      final opened = await openWhatsApp(mobile: family.mobile, text: body);
      if (!opened) {
        if (mounted) SdToast.show(context, l10n.msgOpenFailed);
        return;
      }
      await ref.read(messageRepositoryProvider).recordSent(family, _date, body: body);
      _changed();
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy.remove(family.key));
    }
  }

  Future<void> _copy(AbsentFamily family, String text) async {
    final l10n = AppLocalizations.of(context);
    try {
      await copyText(text);
      await ref.read(messageRepositoryProvider).recordSent(family, _date, body: text, channel: 'copy');
      if (mounted) SdToast.show(context, l10n.msgCopied);
      _changed();
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    }
  }

  Future<void> _preview(AbsentFamily family) async {
    final result = await SdSheet.show<(String, String)>(
      context,
      title: family.names,
      builder: (_) => _PreviewSheet(family: family),
    );
    if (result == null || !mounted) return;
    final (action, edited) = result;
    final text = edited.trim().isEmpty ? family.body : edited.trim();
    if (action == 'send') await _send(family, text: text);
    if (action == 'copy') await _copy(family, text);
  }

  Future<void> _shareSummary(String text, {required bool copy}) async {
    final l10n = AppLocalizations.of(context);
    try {
      if (copy) {
        await copyText(text);
      } else if (!await openWhatsApp(text: text)) {
        if (mounted) SdToast.show(context, l10n.msgOpenFailed);
        return;
      }
      await ref.read(messageRepositoryProvider).recordSummary(_date, text, channel: copy ? 'copy' : 'whatsapp');
      if (!mounted) return;
      ref.read(messagesRevisionProvider.notifier).state++;
      if (copy && mounted) SdToast.show(context, l10n.msgCopied);
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SdPage(
      children: [
        Row(children: [
          Expanded(child: Text(l10n.navMessages, style: theme.textTheme.headlineSmall)),
          SdButton(
            label: l10n.msgTemplatesButton,
            icon: Icons.edit_note_outlined,
            variant: SdButtonVariant.secondary,
            onPressed: () => context.go('/messages/templates?from=messages'),
          ),
        ]),
        const SizedBox(height: SdSpace.lg),
        Wrap(spacing: SdSpace.sm, children: [
          ChoiceChip(
            avatar: const Icon(Icons.send_outlined, size: 18),
            label: Text(l10n.msgTabSend),
            selected: _tab == _Tab.send,
            onSelected: (_) => setState(() => _tab = _Tab.send),
          ),
          ChoiceChip(
            avatar: const Icon(Icons.history, size: 18),
            label: Text(l10n.msgTabHistory),
            selected: _tab == _Tab.history,
            onSelected: (_) => setState(() => _tab = _Tab.history),
          ),
        ]),
        const SizedBox(height: SdSpace.lg),
        if (_tab == _Tab.send) ..._sendView(l10n, theme) else ..._historyView(l10n, theme),
      ],
    );
  }

  List<Widget> _sendView(AppLocalizations l10n, ThemeData theme) {
    final today = _today();
    final isToday = _date == today;
    final sd = SdColors.of(context);
    final institution = ref.watch(activeOrganizationProvider).name;
    return [
      Row(children: [
        IconButton(
          tooltip: l10n.msgPreviousDay,
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _setDate(_date.subtract(const Duration(days: 1))),
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
              if (picked != null) _setDate(picked);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SdSpace.sm),
              child: Text(
                isToday
                    ? '${l10n.attendanceToday}, ${DateFormat('d MMM y').format(_date)}'
                    : DateFormat('EEEE, d MMM y').format(_date),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.msgNextDay,
          icon: const Icon(Icons.chevron_right),
          onPressed: isToday ? null : () => _setDate(_date.add(const Duration(days: 1))),
        ),
      ]),
      const SizedBox(height: SdSpace.lg),

      // Day summary for the staff / principal group.
      FutureBuilder<DaySummary>(
        future: _summary,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(l10n.saveFailed);
          if (!snapshot.hasData) return const SdSkeleton(height: 120);
          final text = daySummaryText(l10n, snapshot.data!, institution: institution);
          return SdSection(
            title: l10n.msgSummaryTitle,
            child: SdCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l10n.msgSummaryHint, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
                const SizedBox(height: SdSpace.md),
                Container(
                  padding: const EdgeInsets.all(SdSpace.md),
                  decoration: BoxDecoration(color: sd.subtleFill, borderRadius: BorderRadius.circular(SdRadius.sm)),
                  child: SelectableText(text, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: SdSpace.md),
                Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
                  SdButton(
                    label: l10n.msgShareWhatsApp,
                    icon: Icons.send_outlined,
                    onPressed: snapshot.data!.anyMarked ? () => _shareSummary(text, copy: false) : null,
                  ),
                  SdButton(
                    label: l10n.msgCopy,
                    icon: Icons.copy_outlined,
                    variant: SdButtonVariant.secondary,
                    onPressed: snapshot.data!.anyMarked ? () => _shareSummary(text, copy: true) : null,
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
      const SizedBox(height: SdSpace.xxl),

      // One message per parent.
      FutureBuilder<List<AbsentFamily>>(
        future: _families,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(l10n.saveFailed);
          if (!snapshot.hasData) {
            return Column(children: [
              for (var i = 0; i < 4; i++)
                const Padding(padding: EdgeInsets.only(bottom: SdSpace.md), child: SdSkeleton(height: 56)),
            ]);
          }
          final all = snapshot.data!;
          if (all.isEmpty) {
            return SdEmptyState(
              icon: Icons.mark_chat_read_outlined,
              title: l10n.msgNoAbsent,
              message: l10n.msgNoAbsentHint,
              action: SdButton(
                label: l10n.actionMarkAttendance,
                variant: SdButtonVariant.secondary,
                onPressed: () => context.go('/attendance'),
              ),
            );
          }
          final withNumber = all.where((f) => f.hasNumber).toList();
          final noNumber = all.where((f) => !f.hasNumber).toList();
          final sent = withNumber.where((f) => f.isSent).length;
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
                      _FamilyTile(
                        family: withNumber[i],
                        busy: _busy.contains(withNumber[i].key),
                        onSend: () => _send(withNumber[i]),
                        onOpen: () => _preview(withNumber[i]),
                      ),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(SdSpace.lg, SdSpace.md, SdSpace.lg, 0),
                      child: Text(l10n.msgNoNumberHint, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
                    ),
                    for (final f in noNumber)
                      ListTile(
                        leading: Icon(Icons.phone_disabled_outlined, color: sd.leave),
                        title: Text(f.names),
                        subtitle: Text(f.students.map((s) => s.className).toSet().join(' / ')),
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
    ];
  }

  // --------------------------------------------------------------- history

  (DateTime?, DateTime?) _range() {
    final now = DateTime.now();
    return switch (_period) {
      _Period.today => (_today(), _today()),
      _Period.month => (DateTime(now.year, now.month), _today()),
      _Period.all => (null, null),
    };
  }

  Future<void> _export(List<MessageRecord> items, {required bool excel}) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _exporting = true);
    try {
      final (from, to) = _range();
      final data = messageHistoryDataset(l10n, items, from: from, to: to);
      final head = await reportLetterhead(ref);
      final saved = excel
          ? await ReportOutput.saveExcel(data, head, title: l10n.exportExcel)
          : await ReportOutput.savePdf(data, head, title: l10n.reportSavePdf);
      if (saved && mounted) SdToast.show(context, l10n.exported);
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showRecord(MessageRecord r) {
    final l10n = AppLocalizations.of(context);
    SdSheet.show<void>(
      context,
      title: r.studentNames.isEmpty ? messageKindLabel(l10n, r.kind) : r.studentNames.join(', '),
      builder: (sheet) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: SdSpace.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                [
                  messageKindLabel(l10n, r.kind),
                  DateFormat('d MMM y, h:mm a').format(r.sentAt.toLocal()),
                  messageChannelLabel(l10n, r.channel),
                  if (r.recipientName != null) r.recipientName!,
                  if (r.mobile != null) r.mobile!,
                ].join(' · '),
                style: Theme.of(sheet).textTheme.bodySmall,
              ),
              const SizedBox(height: SdSpace.md),
              SelectableText(r.body),
              const SizedBox(height: SdSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: SdButton(
                  label: l10n.msgCopy,
                  icon: Icons.copy_outlined,
                  variant: SdButtonVariant.secondary,
                  onPressed: () async {
                    await copyText(r.body);
                    if (sheet.mounted) Navigator.of(sheet).pop();
                    if (mounted) SdToast.show(context, l10n.msgCopied);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _historyView(AppLocalizations l10n, ThemeData theme) {
    ref.watch(messagesRevisionProvider);
    final (from, to) = _range();
    final sd = SdColors.of(context);
    return [
      Wrap(spacing: SdSpace.sm, children: [
        for (final (p, label) in [
          (_Period.today, l10n.msgPeriodToday),
          (_Period.month, l10n.msgPeriodMonth),
          (_Period.all, l10n.msgPeriodAll),
        ])
          ChoiceChip(label: Text(label), selected: _period == p, onSelected: (_) => setState(() => _period = p)),
      ]),
      const SizedBox(height: SdSpace.md),
      SdTextField(hint: l10n.msgHistorySearch, prefixIcon: Icons.search, onChanged: (v) => setState(() => _query = v.trim())),
      const SizedBox(height: SdSpace.md),
      FutureBuilder<List<MessageRecord>>(
        future: ref.read(messageRepositoryProvider).history(from: from, to: to, query: _query),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(l10n.saveFailed);
          if (!snapshot.hasData) return const SdSkeleton(height: 200);
          final items = snapshot.data!;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
              SdButton(
                label: l10n.exportExcel,
                icon: Icons.table_chart_outlined,
                variant: SdButtonVariant.secondary,
                onPressed: _exporting || items.isEmpty ? null : () => _export(items, excel: true),
              ),
              SdButton(
                label: l10n.reportSavePdf,
                icon: Icons.picture_as_pdf_outlined,
                variant: SdButtonVariant.secondary,
                onPressed: _exporting || items.isEmpty ? null : () => _export(items, excel: false),
              ),
            ]),
            const SizedBox(height: SdSpace.lg),
            if (items.isEmpty)
              SdEmptyState(icon: Icons.forum_outlined, title: l10n.msgHistoryEmpty, message: '')
            else
              SdSection(
                title: '${l10n.msgTabHistory} (${items.length})',
                child: SdCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          switch (items[i].kind) {
                            MessageKind.summary => Icons.summarize_outlined,
                            MessageKind.streak => Icons.warning_amber_outlined,
                            MessageKind.absent => Icons.chat_outlined,
                            MessageKind.feeDue => Icons.currency_rupee,
                          },
                          color: items[i].kind == MessageKind.streak ? sd.absent : null,
                        ),
                        title: Text(
                          items[i].studentNames.isEmpty ? messageKindLabel(l10n, items[i].kind) : items[i].studentNames.join(', '),
                        ),
                        subtitle: Text([
                          DateFormat('d MMM y').format(items[i].forDate),
                          if (items[i].classNames.isNotEmpty) items[i].classNames.join(' / '),
                          if (items[i].mobile != null) items[i].mobile!,
                          messageChannelLabel(l10n, items[i].channel),
                        ].join(' · ')),
                        trailing: Text(
                          DateFormat('h:mm a').format(items[i].sentAt.toLocal()),
                          style: theme.textTheme.bodySmall,
                        ),
                        onTap: () => _showRecord(items[i]),
                      ),
                    ],
                  ]),
                ),
              ),
          ]);
        },
      ),
    ];
  }
}

class _FamilyTile extends StatelessWidget {
  const _FamilyTile({required this.family, required this.busy, required this.onSend, required this.onOpen});

  final AbsentFamily family;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sd = SdColors.of(context);
    final classes = family.students.map((s) => s.className).toSet().join(' / ');
    final streak = family.kind == MessageKind.streak;
    final days = family.students.map((s) => s.streak).reduce((a, b) => a < b ? a : b);
    return ListTile(
      onTap: onOpen,
      leading: Icon(
        family.isSent ? Icons.check_circle : Icons.chat_outlined,
        color: family.isSent ? sd.present : sd.textMuted,
      ),
      title: Text(family.names),
      subtitle: Text([
        classes,
        if (family.recipientName != null) family.recipientName!,
        family.mobile ?? '',
        if (family.isSent) l10n.msgSentAt(DateFormat('h:mm a').format(family.sentAt!.toLocal())),
      ].where((s) => s.isNotEmpty).join(' · ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (streak) ...[
          StatusPill(text: l10n.msgStreakBadge(days), color: sd.absent),
          const SizedBox(width: SdSpace.sm),
        ],
        if (busy)
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
        else if (family.isSent)
          IconButton(tooltip: l10n.msgSendAgain, icon: const Icon(Icons.refresh), onPressed: onSend)
        else
          IconButton.filled(tooltip: l10n.msgSend, icon: const Icon(Icons.send), onPressed: onSend),
      ]),
    );
  }
}

/// The message for one family, editable before sending or copying.
/// Pops ('send' | 'copy', text).
class _PreviewSheet extends StatefulWidget {
  const _PreviewSheet({required this.family});

  final AbsentFamily family;

  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.family.body);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final family = widget.family;
    return Padding(
      padding: EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [family.recipientName, family.mobile].whereType<String>().join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: SdSpace.md),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 12,
              decoration: InputDecoration(labelText: l10n.msgPreviewTitle, helperText: l10n.msgEditHint),
            ),
            const SizedBox(height: SdSpace.lg),
            Wrap(
              spacing: SdSpace.sm,
              runSpacing: SdSpace.sm,
              alignment: WrapAlignment.end,
              children: [
                SdButton(
                  label: l10n.msgCopy,
                  icon: Icons.copy_outlined,
                  variant: SdButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(('copy', _controller.text)),
                ),
                SdButton(
                  label: l10n.msgSend,
                  icon: Icons.send_outlined,
                  onPressed: family.mobile == null ? null : () => Navigator.of(context).pop(('send', _controller.text)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
