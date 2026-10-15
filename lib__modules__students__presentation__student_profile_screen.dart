import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/modules/module_providers.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../certificates/application/certificates_providers.dart';
import '../../certificates/domain/certificate_models.dart';
import '../../fees/application/fees_providers.dart';
import '../../fees/domain/fee_models.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_models.dart';
import '../../attendance/presentation/attendance_labels.dart';
import '../application/students_providers.dart';
import '../domain/student_models.dart';
import 'student_labels.dart';

class StudentProfileScreen extends ConsumerStatefulWidget {
  const StudentProfileScreen({super.key, required this.studentId});

  final String studentId;

  @override
  ConsumerState<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen> {
  Future<(StudentDetail?, Map<String, String>)>? _future;
  int? _loadedRevision;
  String? _revealedAadhaar;

  Future<(StudentDetail?, Map<String, String>)> _load(int revision) {
    if (_future == null || _loadedRevision != revision) {
      _loadedRevision = revision;
      _future = () async {
        final detail = await ref.read(studentRepositoryProvider).load(widget.studentId);
        final labels = await ref.read(academicRepositoryProvider).divisionLabels();
        return (detail, labels);
      }();
    }
    return _future!;
  }

  void _changed() => ref.read(studentsRevisionProvider.notifier).state++;

  Future<void> _markLeft(StudentDetail detail) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<(DateTime, String)>(context: context, builder: (_) => const _MarkLeftDialog());
    if (result == null || !mounted) return;
    try {
      await ref.read(studentRepositoryProvider).markLeft(detail.id, date: result.$1, reason: result.$2);
      _changed();
      if (mounted) SdToast.show(context, l10n.studentMarkedLeft);
    } catch (e) {
      if (mounted) SdToast.show(context, studentErrorMessage(l10n, e));
    }
  }

  Future<void> _delete(StudentDetail detail) async {
    final l10n = AppLocalizations.of(context);
    final ok = await SdDialog.confirm(
      context,
      title: l10n.studentDelete,
      message: l10n.studentDeleteMessage,
      confirmLabel: l10n.studentDelete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(studentRepositoryProvider).moveToRecycleBin(detail.id);
    _changed();
    if (!mounted) return;
    SdToast.show(context, l10n.studentDeleted);
    context.go('/students');
  }

  Future<void> _reveal(StudentDetail detail) async {
    final l10n = AppLocalizations.of(context);
    final can = ref.read(permissionCheckerProvider)('students.view_sensitive');
    if (!can) return;
    final value = await ref.read(studentRepositoryProvider).revealAadhaar(detail.id);
    if (!mounted) return;
    setState(() => _revealedAadhaar = value);
    SdToast.show(context, l10n.aadhaarRevealed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final academic = ref.watch(academicControllerProvider);
    final mediaDir = ref.watch(startupStateProvider).mediaDir;
    final canSeeSensitive = ref.watch(permissionCheckerProvider)('students.view_sensitive');
    final future = _load(ref.watch(studentsRevisionProvider));
    final dates = DateFormat('d MMM y');
    String? date(DateTime? d) => d == null ? null : dates.format(d);

    return FutureBuilder<(StudentDetail?, Map<String, String>)>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SdPage(children: [SdSkeleton(height: 96), SizedBox(height: SdSpace.lg), SdSkeleton(height: 240)]);
        }
        final (detail, labels) = snapshot.data!;
        if (detail == null) {
          return SdPage(children: [
            SdEmptyState(
              icon: Icons.person_off_outlined,
              title: l10n.studentNotFound,
              message: '',
              action: SdButton(label: l10n.back, onPressed: () => context.go('/students')),
            ),
          ]);
        }
        final d = detail.draft;
        final active = detail.activeEnrollment;
        final theme = Theme.of(context);
        final sd = SdColors.of(context);
        final fullName = d.fullName;

        return SdPage(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: l10n.back,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/students'),
                ),
                const Spacer(),
                SdButton(
                  label: l10n.studentEditTitle,
                  icon: Icons.edit_outlined,
                  variant: SdButtonVariant.secondary,
                  onPressed: () => context.go('/students/${detail.id}/edit'),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'left') _markLeft(detail);
                    if (v == 'delete') _delete(detail);
                    if (v == 'certificate') context.go('/certificates/new?student=${detail.id}');
                    if (v == 'fees') context.go('/fees/student/${detail.id}');
                    if (v == 'pay') context.go('/fees/pay?student=${detail.id}');
                  },
                  itemBuilder: (_) => [
                    if (ref.read(enabledModulesProvider).contains('fees')) ...[
                      PopupMenuItem(value: 'fees', child: Text(l10n.feeStudentTitle)),
                      PopupMenuItem(value: 'pay', child: Text(l10n.feeTakePayment)),
                    ],
                    if (ref.read(enabledModulesProvider).contains('certificates'))
                      PopupMenuItem(value: 'certificate', child: Text(l10n.certIssue)),
                    if (detail.status == StudentStatus.active)
                      PopupMenuItem(value: 'left', child: Text(l10n.studentMarkLeft)),
                    PopupMenuItem(value: 'delete', child: Text(l10n.studentDelete)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: SdSpace.md),
            Row(
              children: [
                StudentAvatar(name: fullName, photo: studentPhoto(mediaDir, d.photoFileName), size: 72),
                const SizedBox(width: SdSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fullName, style: theme.textTheme.headlineSmall),
                      if (d.altName.isNotEmpty) Text(d.altName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: SdSpace.xs),
                      Text(
                        [
                          detail.displayCode,
                          if (active != null) labels[active.divisionId] ?? placementName(academic, active.divisionId) ?? '',
                          if (active?.rollNumber != null) l10n.rollShort(active!.rollNumber!),
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: theme.textTheme.bodyMedium?.copyWith(color: sd.textMuted),
                      ),
                      if (detail.status != StudentStatus.active) ...[
                        const SizedBox(height: SdSpace.xs),
                        StatusPill(text: studentStatusLabel(l10n, detail.status), color: sd.absent),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: SdSpace.xl),
            if (detail.status == StudentStatus.left)
              _Section(title: l10n.sectionLeaving, children: [
                InfoRow(label: l10n.fieldLeavingDate, value: date(detail.leavingDate)),
                InfoRow(label: l10n.fieldLeavingReason, value: detail.leavingReason),
              ]),
            _Section(title: l10n.sectionPersonal, children: [
              InfoRow(label: l10n.fieldGender, value: d.gender),
              InfoRow(label: l10n.fieldDateOfBirth, value: date(d.dateOfBirth)),
              InfoRow(label: l10n.fieldPlaceOfBirth, value: d.placeOfBirth),
              InfoRow(label: l10n.fieldNationality, value: d.nationality),
              InfoRow(label: l10n.fieldMotherTongue, value: d.motherTongue),
              InfoRow(label: l10n.fieldCategory, value: d.category),
              if (canSeeSensitive) ...[
                InfoRow(label: l10n.fieldCaste, value: d.caste),
                InfoRow(label: l10n.fieldSubCaste, value: d.subCaste),
              ],
              InfoRow(label: l10n.fieldAddress, value: d.address),
            ]),
            _Section(title: l10n.sectionHealth, children: [
              InfoRow(label: l10n.fieldBloodGroup, value: d.bloodGroup),
              InfoRow(label: l10n.fieldHeight, value: d.heightCm?.toStringAsFixed(1)),
              InfoRow(label: l10n.fieldWeight, value: d.weightKg?.toStringAsFixed(1)),
              InfoRow(label: l10n.fieldMeasuredOn, value: date(d.measuredOn)),
            ]),
            _Section(title: l10n.sectionGuardians, children: [
              if (detail.guardians.isEmpty) InfoRow(label: l10n.sectionGuardians, value: null),
              for (final g in detail.guardians)
                Padding(
                  padding: const EdgeInsets.only(bottom: SdSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('${g.name} (${g.relation})', style: theme.textTheme.titleSmall),
                        if (g.isPrimary) ...[
                          const SizedBox(width: SdSpace.sm),
                          StatusPill(text: l10n.fieldPrimaryContact, color: theme.colorScheme.primary),
                        ],
                      ]),
                      InfoRow(label: l10n.fieldMobile, value: g.mobile),
                      if (g.altMobile != null) InfoRow(label: l10n.fieldAltMobile, value: g.altMobile),
                      if (g.email != null) InfoRow(label: l10n.fieldEmail, value: g.email),
                      if (g.occupation != null) InfoRow(label: l10n.fieldOccupation, value: g.occupation),
                    ],
                  ),
                ),
            ]),
            _Section(title: l10n.sectionIdentifiers, children: [
              for (final type in IdentifierType.values)
                InfoRow(
                  label: identifierLabel(l10n, type),
                  value: type == IdentifierType.aadhaar && _revealedAadhaar != null
                      ? _revealedAadhaar
                      : detail.identifier(type),
                  trailing: type == IdentifierType.aadhaar &&
                          detail.identifier(type) != null &&
                          _revealedAadhaar == null &&
                          canSeeSensitive
                      ? TextButton(onPressed: () => _reveal(detail), child: Text(l10n.aadhaarReveal))
                      : null,
                ),
            ]),
            if (ref.watch(enabledModulesProvider).contains('attendance'))
              FutureBuilder<(AttendanceSummary, AttendanceSummary, List<DateTime>)>(
                future: _attendance(detail.id, academic.activeYear?.startDate),
                builder: (context, snap) {
                  final data = snap.data;
                  String line(AttendanceSummary s) => s.days == 0
                      ? l10n.attendanceNone
                      : l10n.attendancePercentOf(
                          formatPercent(s.percent),
                          formatPercent(s.present),
                          formatPercent(s.present + s.absent),
                        );
                  return _Section(title: l10n.attendanceSectionTitle, children: [
                    InfoRow(label: l10n.attendanceThisYear, value: data == null ? null : line(data.$1)),
                    InfoRow(label: l10n.attendanceThisMonth, value: data == null ? null : line(data.$2)),
                    InfoRow(
                      label: l10n.attendanceRecentAbsences,
                      value: data == null || data.$3.isEmpty
                          ? null
                          : data.$3.map((d) => DateFormat('d MMM').format(d)).join(', '),
                    ),
                  ]);
                },
              ),
            if (ref.watch(enabledModulesProvider).contains('fees') &&
                ref.watch(academicControllerProvider).activeYear != null)
              FutureBuilder<FeeAccount>(
                future: (() {
                  ref.watch(feesRevisionProvider);
                  return ref
                      .read(feeRepositoryProvider)
                      .account(detail.id, ref.read(academicControllerProvider).activeYear!.id);
                })(),
                builder: (context, snap) {
                  final a = snap.data;
                  if (a == null || (a.due == 0 && a.paid == 0)) return const SizedBox.shrink();
                  return _Section(title: l10n.feeStudentTitle, children: [
                    InkWell(
                      onTap: () => context.go('/fees/student/${detail.id}'),
                      child: Column(children: [
                        InfoRow(label: l10n.feeDue, value: rupees(a.due)),
                        InfoRow(label: l10n.feePaid, value: rupees(a.paid)),
                        InfoRow(
                          label: l10n.feeBalance,
                          value: a.overdue > 0 ? '${rupees(a.balance)} (${l10n.feeOverdue} ${rupees(a.overdue)})' : rupees(a.balance),
                        ),
                      ]),
                    ),
                  ]);
                },
              ),
            if (ref.watch(enabledModulesProvider).contains('certificates'))
              FutureBuilder<List<CertificateRecord>>(
                future: ref.read(certificateRepositoryProvider).list(studentId: detail.id),
                builder: (context, snap) {
                  final certs = snap.data ?? const <CertificateRecord>[];
                  if (certs.isEmpty) return const SizedBox.shrink();
                  return _Section(title: l10n.certStudentSection, children: [
                    for (final c in certs)
                      InkWell(
                        onTap: () => context.go('/certificates/view/${c.id}'),
                        child: InfoRow(
                          label: DateFormat('d MMM y').format(c.issuedOn),
                          value: '${certificateTitle(l10n, c.kind).split(' (').first} · ${c.serialLabel}'
                              '${c.status == CertificateStatus.cancelled ? ' · ${l10n.certCancelled}' : ''}'
                              '${c.isDuplicate ? ' · ${l10n.certDuplicate}' : ''}',
                        ),
                      ),
                  ]);
                },
              ),
            _Section(title: l10n.sectionAdmission, children: [
              InfoRow(label: l10n.fieldAdmissionDate, value: date(d.admissionDate)),
              InfoRow(label: l10n.fieldPreviousSchool, value: d.previousSchool),
            ]),
            _Section(title: l10n.sectionHistory, children: [
              if (detail.enrollments.isEmpty) InfoRow(label: l10n.sectionPlacement, value: l10n.placementNone),
              for (final e in detail.enrollments)
                InfoRow(
                  label: academic.years.where((y) => y.id == e.academicYearId).firstOrNull?.label ?? '',
                  value: [
                    labels[e.divisionId] ?? '',
                    if (e.rollNumber != null) l10n.rollShort(e.rollNumber!),
                    enrollmentStatusLabel(l10n, e.status),
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
            ]),
            FutureBuilder<List<ExtraFieldDefinition>>(
              future: ref.watch(extraFieldsProvider.future),
              builder: (context, extra) {
                final fields = extra.data ?? const <ExtraFieldDefinition>[];
                if (fields.isEmpty) return const SizedBox.shrink();
                return _Section(title: l10n.sectionExtra, children: [
                  for (final f in fields) InfoRow(label: f.label, value: _extraDisplay(l10n, f, d.extra[f.key])),
                ]);
              },
            ),
            if (d.notes.isNotEmpty) _Section(title: l10n.sectionNotes, children: [Text(d.notes)]),
          ],
        );
      },
    );
  }

  Future<(AttendanceSummary, AttendanceSummary, List<DateTime>)>? _attendanceFuture;
  String? _attendanceKey;

  Future<(AttendanceSummary, AttendanceSummary, List<DateTime>)> _attendance(String studentId, DateTime? yearStart) {
    final key = '$studentId|$yearStart|${ref.read(attendanceRevisionProvider)}';
    if (_attendanceFuture == null || key != _attendanceKey) {
      _attendanceKey = key;
      final repo = ref.read(attendanceRepositoryProvider);
      final now = DateTime.now();
      _attendanceFuture = _loadAttendance(repo, studentId, yearStart ?? DateTime(now.year - 1, now.month), now);
    }
    return _attendanceFuture!;
  }

  static Future<(AttendanceSummary, AttendanceSummary, List<DateTime>)> _loadAttendance(
    AttendanceRepository repo,
    String studentId,
    DateTime yearStart,
    DateTime now,
  ) async {
    final year = await repo.studentSummary(studentId, from: yearStart, to: now);
    final month = await repo.studentSummary(studentId, from: DateTime(now.year, now.month), to: now);
    final absences = await repo.recentAbsences(studentId);
    return (year, month, absences);
  }

  static String? _extraDisplay(AppLocalizations l10n, ExtraFieldDefinition f, String? value) {
    if (value == null || value.isEmpty) return null;
    if (f.type == 'yesNo') return value == 'true' ? l10n.yes : l10n.no;
    if (f.type == 'date') {
      final parsed = DateTime.tryParse(value);
      return parsed == null ? value : DateFormat('d MMM y').format(parsed);
    }
    return value;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: SdSection(
        title: title,
        child: SdCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
      ),
    );
  }
}

class _MarkLeftDialog extends StatefulWidget {
  const _MarkLeftDialog();

  @override
  State<_MarkLeftDialog> createState() => _MarkLeftDialogState();
}

class _MarkLeftDialogState extends State<_MarkLeftDialog> {
  DateTime _date = DateTime.now();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.studentMarkLeft),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SdDateField(
            label: l10n.fieldLeavingDate,
            value: _date,
            clearable: false,
            onChanged: (d) => setState(() => _date = d ?? _date),
          ),
          TextField(
            controller: _reason,
            decoration: InputDecoration(labelText: l10n.fieldLeavingReason),
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
      actions: [
        SdButton(label: l10n.cancel, variant: SdButtonVariant.text, onPressed: () => Navigator.of(context).pop()),
        SdButton(
          label: l10n.studentMarkLeft,
          variant: SdButtonVariant.danger,
          onPressed: () => Navigator.of(context).pop((_date, _reason.text)),
        ),
      ],
    );
  }
}
