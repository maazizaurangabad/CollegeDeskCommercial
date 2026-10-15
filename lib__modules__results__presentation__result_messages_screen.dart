import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../messages/application/messages_providers.dart';
import '../../messages/domain/message_models.dart';
import '../../students/application/students_providers.dart';
import '../../students/presentation/student_labels.dart';
import '../application/results_providers.dart';
import '../domain/result_models.dart';

/// Results to parents on WhatsApp: one tap per student, text editable,
/// a tick once sent today.
class ResultMessagesScreen extends ConsumerStatefulWidget {
  const ResultMessagesScreen({super.key, required this.divisionId, required this.examKey});

  final String divisionId;

  /// An exam id, or "final".
  final String examKey;

  @override
  ConsumerState<ResultMessagesScreen> createState() => _ResultMessagesScreenState();
}

typedef _Row = ({StudentResult result, String? mobile, DateTime? sentAt});

class _ResultMessagesScreenState extends ConsumerState<ResultMessagesScreen> {
  late Future<({List<_Row> rows, String exam, String classLabel, ResultRules rules})?> _data = _load();
  final Set<String> _busy = {};

  Future<({List<_Row> rows, String exam, String classLabel, ResultRules rules})?> _load() async {
    final l10n = AppLocalizations.of(context);
    final academic = ref.read(academicControllerProvider);
    final year = academic.activeYear;
    final division = academic.divisions.where((d) => d.id == widget.divisionId).firstOrNull;
    if (year == null || division == null) return null;
    final program = academic.programs.where((p) => p.id == division.programId).firstOrNull;
    final repo = ref.read(resultRepositoryProvider);
    final isFinal = widget.examKey == 'final';
    final r = await repo.classResult(
      divisionId: division.id,
      programId: division.programId,
      academicYearId: year.id,
      examId: isFinal ? null : widget.examKey,
    );
    final exams = await repo.exams(year.id);
    final mobiles = {
      for (final s in await ref.read(studentRepositoryProvider).list(academicYearId: year.id)) s.id: s.primaryMobile,
    };
    final sent = await ref.read(messageRepositoryProvider).sentOn(DateTime.now(), {MessageKind.result});
    return (
      rows: [
        for (final x in r.results)
          if (x.status != ResultStatus.incomplete) (result: x, mobile: mobiles[x.studentId], sentAt: sent[x.studentId]),
      ],
      exam: isFinal ? l10n.resFinalResult : exams.where((e) => e.id == widget.examKey).firstOrNull?.name ?? '',
      classLabel: '${program?.name ?? ''} ${division.name}'.trim(),
      rules: await repo.rules(),
    );
  }

  String _body(AppLocalizations l10n, StudentResult r, String exam, String classLabel, ResultRules rules) =>
      l10n.resParentMessage(
        exam,
        r.name,
        classLabel,
        r.total,
        r.maxTotal,
        rules.percentText(r.percent),
        resultStatusLabel(l10n, r.status).toUpperCase(),
        ref.read(activeOrganizationProvider).name,
      );

  Future<void> _send(_Row row, String body) async {
    final l10n = AppLocalizations.of(context);
    final mobile = row.mobile;
    if (mobile == null) return;
    if (row.sentAt != null) {
      final again = await SdDialog.confirm(
        context,
        title: l10n.msgSendAgainTitle,
        message: l10n.resSentAlready,
        confirmLabel: l10n.msgSendAgain,
        cancelLabel: l10n.cancel,
      );
      if (!again || !mounted) return;
    }
    setState(() => _busy.add(row.result.studentId));
    try {
      if (!await openWhatsApp(mobile: mobile, text: body)) {
        if (mounted) SdToast.show(context, l10n.msgOpenFailed);
        return;
      }
      final loaded = await _data;
      await ref.read(messageRepositoryProvider).recordFeeReminder(
            kind: MessageKind.result,
            students: [(row.result.studentId, row.result.name, loaded?.classLabel ?? '')],
            mobile: mobile,
            body: body,
            date: DateTime.now(),
          );
      if (!mounted) return;
      ref.read(messagesRevisionProvider.notifier).state++;
      setState(() => _data = _load());
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy.remove(row.result.studentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    return SdPage(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: SdSpace.lg),
        child: Row(children: [
          IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/results')),
          const SizedBox(width: SdSpace.xs),
          Expanded(child: Text(l10n.resSendToParents, style: theme.textTheme.headlineSmall)),
        ]),
      ),
      FutureBuilder(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(l10n.saveFailed);
          if (snapshot.connectionState != ConnectionState.done) return const SdSkeleton(height: 240);
          final d = snapshot.data;
          if (d == null || d.rows.isEmpty) {
            return SdEmptyState(icon: Icons.emoji_events_outlined, title: l10n.resNothingToSend, message: l10n.resNothingToSendHint);
          }
          final withNumber = d.rows.where((r) => r.mobile != null).toList();
          final sent = withNumber.where((r) => r.sentAt != null).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${d.exam} · ${d.classLabel}', style: theme.textTheme.titleSmall),
            const SizedBox(height: SdSpace.md),
            SdSection(
              title: l10n.msgParentsTitle(d.rows.length),
              trailing: StatusPill(
                text: l10n.msgProgress(sent, withNumber.length),
                color: sent == withNumber.length ? sd.present : sd.info,
              ),
              child: SdCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < d.rows.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    Builder(builder: (context) {
                      final row = d.rows[i];
                      final body = _body(l10n, row.result, d.exam, d.classLabel, d.rules);
                      final busy = _busy.contains(row.result.studentId);
                      return ListTile(
                        leading: Icon(
                          row.sentAt != null ? Icons.check_circle : Icons.chat_outlined,
                          color: row.sentAt != null ? sd.present : sd.textMuted,
                        ),
                        title: Text(row.result.name),
                        subtitle: Text([
                          '${row.result.total}/${row.result.maxTotal} · ${d.rules.percentText(row.result.percent)}%',
                          resultStatusLabel(l10n, row.result.status),
                          row.mobile ?? l10n.resNoMobile,
                          if (row.sentAt != null) l10n.msgSentAt(DateFormat('h:mm a').format(row.sentAt!.toLocal())),
                        ].join(' · ')),
                        trailing: row.mobile == null
                            ? null
                            : busy
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                : IconButton.filled(
                                    tooltip: l10n.msgSend,
                                    icon: Icon(row.sentAt != null ? Icons.refresh : Icons.send),
                                    onPressed: () => _send(row, body),
                                  ),
                      );
                    }),
                  ],
                ]),
              ),
            ),
          ]);
        },
      ),
    ]);
  }
}
