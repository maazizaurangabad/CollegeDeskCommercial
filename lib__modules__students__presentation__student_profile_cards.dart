import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../attendance/domain/attendance_models.dart';
import '../../attendance/presentation/attendance_labels.dart';
import '../../certificates/application/certificates_providers.dart';
import '../../certificates/domain/certificate_models.dart';
import '../../certificates/presentation/certificate_view_screen.dart';
import '../../fees/application/fees_providers.dart';
import '../../fees/domain/fee_models.dart';
import '../../messages/application/messages_providers.dart';
import '../../messages/domain/message_models.dart';
import '../../results/application/results_providers.dart';
import '../../results/data/result_repository.dart';
import '../../results/domain/result_models.dart';
import '../application/student_profile_providers.dart';
import '../application/students_providers.dart';
import '../documents/document_models.dart';
import '../documents/document_providers.dart';
import '../domain/record_completeness.dart';
import '../domain/student_models.dart';
import 'student_labels.dart';

final _date = DateFormat('d MMM y');

/// A titled card on the student profile.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.icon, required this.title, required this.child, this.action});

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: SdSpace.sm),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: SdSpace.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// Loading, error and data for a card body.
Widget profileAsync<T>(BuildContext context, AsyncValue<T> value, Widget Function(T data) data) => value.when(
      loading: () => const SdSkeleton(height: 64),
      error: (e, _) => ProfileNote(icon: Icons.error_outline, text: AppLocalizations.of(context).p360LoadFailed),
      data: data,
    );

/// A quiet one-line message inside a card ("No fees set…").
class ProfileNote extends StatelessWidget {
  const ProfileNote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final sd = SdColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: sd.textMuted),
        const SizedBox(width: SdSpace.sm),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: sd.textMuted))),
      ],
    );
  }
}

/// A label with a large number under it.
class ProfileFigure extends StatelessWidget {
  const ProfileFigure({super.key, required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: SdColors.of(context).textMuted)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

/// A round progress ring with its value in the middle; fills in gently.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.label, this.color, this.size = 76});

  final double value;
  final String label;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: target),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => CircularProgressIndicator(
                value: v,
                strokeWidth: 7,
                strokeCap: StrokeCap.round,
                backgroundColor: SdColors.of(context).subtleFill,
                color: color,
              ),
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ============================================================ completeness

String completenessLabel(AppLocalizations l10n, CompletenessItem item) {
  if (item.extraField != null) return item.extraField!.label;
  return completenessCheckLabel(l10n, item.check!);
}

String completenessCheckLabel(AppLocalizations l10n, CompletenessCheck c) => switch (c) {
      CompletenessCheck.fullName => l10n.p360Name,
      CompletenessCheck.dateOfBirth => l10n.fieldDateOfBirth,
      CompletenessCheck.gender => l10n.fieldGender,
      CompletenessCheck.guardianMobile => l10n.p360CheckGuardianMobile,
      CompletenessCheck.classThisYear => l10n.p360CheckClass,
      CompletenessCheck.grNumber => l10n.idGr,
      CompletenessCheck.motherName => l10n.p360CheckMother,
      CompletenessCheck.fatherName => l10n.fieldFatherName,
      CompletenessCheck.address => l10n.fieldAddress,
      CompletenessCheck.category => l10n.fieldCategory,
      CompletenessCheck.admissionDate => l10n.fieldAdmissionDate,
      CompletenessCheck.aadhaar => l10n.idAadhaar,
      CompletenessCheck.pen => l10n.idPen,
      CompletenessCheck.apaar => l10n.idApaar,
      CompletenessCheck.photo => l10n.p360CheckPhoto,
      CompletenessCheck.requiredDocuments => l10n.p360CheckDocuments,
    };

class CompletenessCard extends ConsumerWidget {
  const CompletenessCard({super.key, required this.detail, required this.yearId, this.programId, this.onFix});

  final StudentDetail detail;
  final String? yearId;

  /// The student's class (program) in the year shown, for document rules.
  final String? programId;

  /// Opens the edit form; null when the user cannot edit.
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final checks = ref.watch(completenessChecksProvider).valueOrNull ?? defaultCompletenessChecks;
    final extra = ref.watch(extraFieldsProvider).valueOrNull ?? const <ExtraFieldDefinition>[];
    int? documentsMissing;
    if (checks.contains(CompletenessCheck.requiredDocuments)) {
      final types = ref.watch(documentTypesProvider).valueOrNull;
      final docs = ref.watch(studentDocumentsProvider(detail.id)).valueOrNull;
      if (types != null && docs != null) {
        documentsMissing = documentChecklist(types, docs, programId: programId, category: detail.draft.category)
            .where(isMissing)
            .length;
      }
    }
    final c = RecordCompleteness.evaluate(
      detail,
      checks: checks,
      extraFields: extra,
      academicYearId: yearId,
      documentsMissing: documentsMissing,
    );
    final color = c.percent == 100 ? sd.present : (c.percent >= 75 ? theme.colorScheme.primary : sd.leave);

    return ProfileCard(
      icon: Icons.task_alt,
      title: l10n.p360Completeness,
      action: TextButton(
        onPressed: () => context.go('/settings/student-fields'),
        child: Text(l10n.p360ChooseChecks),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.p360PercentComplete(c.percent),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(l10n.p360ChecksOf(c.done, c.total), style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
            ],
          ),
          const SizedBox(height: SdSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(SdRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: c.percent / 100),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) =>
                  LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: sd.subtleFill, color: color),
            ),
          ),
          const SizedBox(height: SdSpace.md),
          Wrap(
            spacing: SdSpace.sm,
            runSpacing: SdSpace.sm,
            children: [
              for (final item in c.items)
                _CheckChip(
                  label: completenessLabel(l10n, item),
                  done: item.done,
                  onTap: item.done ? null : onFix,
                ),
            ],
          ),
          const SizedBox(height: SdSpace.md),
          Text(
            c.missing.isEmpty ? l10n.p360CompleteNote : l10n.p360MissingNote,
            style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted),
          ),
        ],
      ),
    );
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.label, required this.done, this.onTap});

  final String label;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sd = SdColors.of(context);
    final color = done ? sd.present : sd.leave;
    final chip = Material(
      color: color.withValues(alpha: 0.12),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(done ? Icons.check_circle : Icons.error_outline, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return chip;
    return Tooltip(message: AppLocalizations.of(context).p360TapToFill, child: chip);
  }
}

// ==================================================================== fees

class FeesSummaryCard extends ConsumerWidget {
  const FeesSummaryCard({super.key, required this.yearKey, required this.yearLabel, this.showReceipts = false});

  final StudentYearKey yearKey;
  final String yearLabel;
  final bool showReceipts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    return ProfileCard(
      icon: Icons.currency_rupee,
      title: l10n.p360FeesTitle(yearLabel),
      action: TextButton(
        onPressed: () => context.go('/fees/student/${yearKey.studentId}'),
        child: Text(l10n.p360OpenFees),
      ),
      child: profileAsync<FeeAccount>(context, ref.watch(studentFeesYearProvider(yearKey)), (a) {
        if (!a.hasStructure && a.due == 0 && a.paid == 0) {
          return ProfileNote(icon: Icons.info_outline, text: l10n.p360FeesNotSet);
        }
        final (statusText, statusColor) = a.balance <= 0
            ? (l10n.p360PaidInFull, sd.present)
            : a.paid == 0
                ? (l10n.p360NotPaid, sd.absent)
                : (l10n.p360PartlyPaid, sd.leave);
        final share = a.due == 0 ? 1.0 : a.paid / a.due;
        final next = a.nextDue;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusPill(text: statusText, color: statusColor),
                      const SizedBox(height: SdSpace.md),
                      Wrap(
                        spacing: SdSpace.xl,
                        runSpacing: SdSpace.md,
                        children: [
                          ProfileFigure(label: l10n.feeDue, value: rupees(a.due)),
                          ProfileFigure(label: l10n.feePaid, value: rupees(a.paid), color: sd.present),
                          ProfileFigure(
                            label: l10n.feeBalance,
                            value: rupees(a.balance),
                            color: a.balance > 0 ? sd.absent : sd.present,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SdSpace.lg),
                ProgressRing(value: share, label: '${(share * 100).clamp(0, 100).round()}%', color: statusColor),
              ],
            ),
            if (a.overdue > 0) ...[
              const SizedBox(height: SdSpace.md),
              Text(l10n.p360Overdue(rupees(a.overdue)), style: theme.textTheme.bodyMedium?.copyWith(color: sd.absent)),
            ],
            if (next != null && a.balance > 0) ...[
              const SizedBox(height: SdSpace.xs),
              Text(
                l10n.p360NextInstallment(next.label, _date.format(next.dueDate)),
                style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted),
              ),
            ],
            if (showReceipts) ...[
              const Divider(height: SdSpace.xl),
              Text(l10n.p360Receipts, style: theme.textTheme.titleSmall),
              const SizedBox(height: SdSpace.xs),
              if (a.receipts.isEmpty) ProfileNote(icon: Icons.receipt_long_outlined, text: l10n.p360NoReceipts),
              for (final r in a.receipts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(r.serialLabel),
                  subtitle: Text(_date.format(r.receivedOn)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (r.isCancelled) ...[
                        StatusPill(text: l10n.certCancelled, color: sd.absent),
                        const SizedBox(width: SdSpace.sm),
                      ],
                      Text(rupees(r.total), style: theme.textTheme.titleSmall),
                    ],
                  ),
                  onTap: () => context.go('/fees/receipt/${r.id}'),
                ),
            ],
          ],
        );
      }),
    );
  }
}

// ============================================================== attendance

class AttendanceSummaryCard extends ConsumerWidget {
  const AttendanceSummaryCard({super.key, required this.yearKey, required this.yearLabel, this.onOpen});

  final StudentYearKey yearKey;
  final String yearLabel;

  /// Opens the register for the student's class; null hides the button.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final codes = {
      for (final c in ref.watch(attendanceCodesProvider).valueOrNull ?? const <AttendanceCode>[]) c.code: c,
    };
    return ProfileCard(
      icon: Icons.fact_check_outlined,
      title: l10n.p360AttendanceTitle(yearLabel),
      action: onOpen == null ? null : TextButton(onPressed: onOpen, child: Text(l10n.p360OpenAttendance)),
      child: profileAsync(context, ref.watch(studentAttendanceYearProvider(yearKey)), (data) {
        if (data == null || data.summary.days == 0) {
          return ProfileNote(icon: Icons.event_busy_outlined, text: l10n.p360AttendanceNone);
        }
        final s = data.summary;
        final pct = s.percent;
        final color = pct == null ? sd.textMuted : (pct >= 75 ? sd.present : sd.absent);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProgressRing(value: (pct ?? 0) / 100, label: '${formatPercent(pct)}%', color: color),
                const SizedBox(width: SdSpace.lg),
                Expanded(
                  child: Wrap(
                    spacing: SdSpace.xl,
                    runSpacing: SdSpace.md,
                    children: [
                      ProfileFigure(label: l10n.countsPresent, value: formatPercent(s.present), color: sd.present),
                      ProfileFigure(label: l10n.countsAbsent, value: formatPercent(s.absent), color: sd.absent),
                      ProfileFigure(label: l10n.p360LeaveNotCounted, value: '${s.excluded}'),
                      ProfileFigure(label: l10n.p360DaysMarked, value: '${s.days}'),
                    ],
                  ),
                ),
              ],
            ),
            if (pct != null && pct < 75) ...[
              const SizedBox(height: SdSpace.md),
              Text(l10n.p360Below75, style: theme.textTheme.bodyMedium?.copyWith(color: sd.absent)),
            ],
            if (data.recent.isNotEmpty) ...[
              const SizedBox(height: SdSpace.md),
              Text(l10n.p360RecentDays, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
              const SizedBox(height: SdSpace.xs),
              Wrap(
                spacing: SdSpace.xs,
                runSpacing: SdSpace.xs,
                children: [
                  for (final (day, code) in data.recent)
                    Tooltip(
                      message: codes[code]?.label ?? code,
                      child: StatusPill(
                        text: '${DateFormat('d MMM').format(day)} · $code',
                        color: codes[code] == null ? sd.textMuted : Color(codes[code]!.colorValue),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      }),
    );
  }
}

// ================================================================= results

Color resultColor(SdColors sd, ResultStatus s) => switch (s) {
      ResultStatus.passed => sd.present,
      ResultStatus.failed => sd.absent,
      ResultStatus.atkt => sd.leave,
      ResultStatus.incomplete => sd.textMuted,
    };

class ResultsSummaryCard extends ConsumerWidget {
  const ResultsSummaryCard({super.key, required this.yearKey, required this.yearLabel, this.latestOnly = false});

  final StudentYearKey yearKey;
  final String yearLabel;

  /// Only the newest line (Overview).
  final bool latestOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ProfileCard(
      icon: Icons.emoji_events_outlined,
      title: l10n.p360ResultsTitle(yearLabel),
      action: TextButton(onPressed: () => context.go('/results'), child: Text(l10n.p360OpenResults)),
      child: profileAsync(context, ref.watch(studentResultsYearProvider(yearKey)), (data) {
        if (data == null || data.lines.isEmpty) {
          return ProfileNote(icon: Icons.hourglass_empty, text: l10n.p360ResultsNone);
        }
        final lines = latestOnly ? [data.lines.last] : data.lines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const Divider(height: SdSpace.lg),
              _ResultLine(line: lines[i], rules: data.rules),
            ],
          ],
        );
      }),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.line, required this.rules});

  final StudentExamResult line;
  final ResultRules rules;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final r = line.result;
    final complete = r.status != ResultStatus.incomplete;
    final details = complete
        ? [
            '${r.total} / ${r.maxTotal}',
            '${rules.percentText(r.percent)}%',
            if (r.resultClass != null) resultClassLabel(l10n, r.resultClass!),
            if (r.rank != null) l10n.p360Rank(r.rank!),
          ].join(' · ')
        : l10n.p360MarksPending;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.exam?.name ?? l10n.resFinalResult,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: line.exam == null ? FontWeight.w700 : null),
              ),
              const SizedBox(height: 2),
              Text(details, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
            ],
          ),
        ),
        StatusPill(text: resultStatusLabel(l10n, r.status), color: resultColor(sd, r.status)),
      ],
    );
  }
}

// ============================================================ certificates

class CertificatesCard extends ConsumerWidget {
  const CertificatesCard({super.key, required this.studentId, this.limit, this.onIssue});

  final String studentId;

  /// Show only the newest few (Overview).
  final int? limit;

  /// Opens the issue screen with this student; null hides the button.
  final VoidCallback? onIssue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sd = SdColors.of(context);
    return ProfileCard(
      icon: Icons.workspace_premium_outlined,
      title: l10n.certStudentSection,
      action: onIssue == null ? null : TextButton(onPressed: onIssue, child: Text(l10n.p360MakeCertificate)),
      child: profileAsync<List<CertificateRecord>>(context, ref.watch(studentCertificatesProvider(studentId)), (certs) {
        if (certs.isEmpty) return ProfileNote(icon: Icons.description_outlined, text: l10n.p360CertificatesNone);
        final shown = limit == null ? certs : certs.take(limit!).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in shown)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.description_outlined),
                title: Text(certificateTitle(l10n, c.kind).split(' (').first),
                subtitle: Text('${c.serialLabel} · ${_date.format(c.issuedOn)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.status == CertificateStatus.cancelled)
                      StatusPill(text: l10n.certCancelled, color: sd.absent)
                    else if (c.isDuplicate)
                      StatusPill(text: l10n.certDuplicate, color: sd.leave)
                    else
                      StatusPill(text: l10n.p360Issued, color: sd.present),
                    IconButton(
                      tooltip: l10n.certView,
                      icon: const Icon(Icons.visibility_outlined),
                      onPressed: () => openCertificateView(context, c.id),
                    ),
                  ],
                ),
                onTap: () => openCertificateView(context, c.id),
              ),
            if (limit != null && certs.length > limit!)
              Text(l10n.p360MoreCertificates(certs.length - limit!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: sd.textMuted)),
          ],
        );
      }),
    );
  }
}

// ================================================================ messages

class MessagesCard extends ConsumerWidget {
  const MessagesCard({super.key, required this.yearKey, required this.yearLabel});

  final StudentYearKey yearKey;
  final String yearLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    return ProfileCard(
      icon: Icons.forum_outlined,
      title: l10n.p360MessagesTitle(yearLabel),
      child: profileAsync<List<MessageRecord>>(context, ref.watch(studentMessagesYearProvider(yearKey)), (list) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (list.isEmpty) ProfileNote(icon: Icons.chat_bubble_outline, text: l10n.p360MessagesNone),
            for (final m in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(m.channel == 'copy' ? Icons.copy_outlined : Icons.chat_outlined),
                title: Text(messageKindLabel(l10n, m.kind)),
                subtitle: Text([
                  _date.format(m.forDate),
                  if ((m.recipientName ?? '').isNotEmpty) m.recipientName!,
                  if ((m.mobile ?? '').isNotEmpty) m.mobile!,
                ].join(' · ')),
                trailing: StatusPill(
                  text: m.channel == 'copy' ? l10n.msgCopied : l10n.p360OpenedInWhatsApp,
                  color: sd.info,
                ),
              ),
            const SizedBox(height: SdSpace.sm),
            Text(l10n.msgHistoryNote, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
          ],
        );
      }),
    );
  }
}
