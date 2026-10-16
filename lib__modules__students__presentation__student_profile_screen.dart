import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ids/uuid7.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/academic/academic_models.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/modules/module_providers.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../../platform/reporting/report_pdf_preview.dart';
import '../../messages/application/messages_providers.dart';
import '../../reports/application/reports_providers.dart';
import '../application/student_profile_providers.dart';
import '../application/student_profile_report.dart';
import '../application/students_providers.dart';
import '../domain/student_models.dart';
import '../documents/student_documents_section.dart';
import '../import/photo_resize.dart';
import 'student_labels.dart';
import 'student_profile_cards.dart';

/// Parts of the Student 360° profile, in menu order.
enum _Part { overview, personal, academic, documents, attendance, fees, results, certificates, messages, history }

/// Last part and year shown, so coming back from Fees, Attendance or a
/// certificate opens the profile where the user left it.
final _lastView = StateProvider<({String studentId, _Part part, String? yearId})?>((ref) => null);

/// Student 360°: everything about one student in one place. Only reads;
/// every figure comes from the module that owns it.
class StudentProfileScreen extends ConsumerStatefulWidget {
  const StudentProfileScreen({super.key, required this.studentId});

  final String studentId;

  @override
  ConsumerState<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen> {
  _Part _part = _Part.overview;
  String? _yearId;
  String? _revealedAadhaar;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    final last = ref.read(_lastView);
    if (last != null && last.studentId == widget.studentId) {
      _part = last.part;
      _yearId = last.yearId;
    }
  }

  void _remember() =>
      ref.read(_lastView.notifier).state = (studentId: widget.studentId, part: _part, yearId: _yearId);

  void _changed() => ref.read(studentsRevisionProvider.notifier).state++;

  bool _can(String permission) => ref.read(permissionCheckerProvider)(permission);

  // ================================================================ actions

  /// Guardian numbers, primary guardian first: (who, number).
  List<(String, String)> _contacts(AppLocalizations l10n, StudentDetail detail) {
    final guardians = [...detail.guardians]..sort((a, b) => (b.isPrimary ? 1 : 0).compareTo(a.isPrimary ? 1 : 0));
    return [
      for (final g in guardians) ...[
        if ((g.mobile ?? '').trim().isNotEmpty) ('${g.name} (${g.relation})', g.mobile!.trim()),
        if ((g.altMobile ?? '').trim().isNotEmpty) ('${g.name} (${g.relation}) · ${l10n.fieldAltMobile}', g.altMobile!.trim()),
      ],
    ];
  }

  Future<String?> _chooseNumber(AppLocalizations l10n, List<(String, String)> contacts) async {
    if (contacts.isEmpty) return null;
    if (contacts.length == 1) return contacts.single.$2;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SdSpace.lg),
              child: Text(l10n.p360ChooseNumber, style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: SdSpace.sm),
            for (final (who, number) in contacts)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(who),
                subtitle: Text(number),
                onTap: () => Navigator.of(context).pop(number),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _call(StudentDetail detail) async {
    final l10n = AppLocalizations.of(context);
    final number = await _chooseNumber(l10n, _contacts(l10n, detail));
    if (number == null || !mounted) return;
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && mounted) SdToast.show(context, l10n.p360CallFailed);
  }

  Future<void> _whatsApp(StudentDetail detail) async {
    final l10n = AppLocalizations.of(context);
    final number = await _chooseNumber(l10n, _contacts(l10n, detail));
    if (number == null || !mounted) return;
    final ok = await openWhatsApp(mobile: number, text: '');
    if (!mounted) return;
    SdToast.show(context, ok ? l10n.p360WhatsAppOpened : l10n.msgOpenFailed);
  }

  /// Name, code, G.R., class, date of birth and guardian numbers.
  /// Never Aadhaar.
  Future<void> _copy(StudentDetail detail, String? classLine) async {
    final l10n = AppLocalizations.of(context);
    final d = detail.draft;
    final text = [
      '${l10n.p360Name}: ${d.fullName}',
      '${l10n.p360StudentCode}: ${detail.displayCode}',
      if (detail.identifier(IdentifierType.grNumber) case final gr?) '${l10n.idGr}: $gr',
      if (classLine != null && classLine.isNotEmpty) '${l10n.fieldClass}: $classLine',
      if (d.dateOfBirth != null) '${l10n.fieldDateOfBirth}: ${DateFormat('dd/MM/yyyy').format(d.dateOfBirth!)}',
      for (final (who, number) in _contacts(l10n, detail)) '$who: $number',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) SdToast.show(context, l10n.p360Copied);
  }

  Future<void> _changePhoto(StudentDetail detail) async {
    final l10n = AppLocalizations.of(context);
    final mediaDir = ref.read(startupStateProvider).mediaDir;
    if (mediaDir == null) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      final bytes = await resizeStudentPhoto(await File(path).readAsBytes());
      if (bytes == null) {
        if (mounted) SdToast.show(context, l10n.p360PhotoUnreadable);
        return;
      }
      final name = 'students/${Uuid7.generate()}.jpg';
      final file = File(p.join(mediaDir.path, name));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      await ref.read(studentRepositoryProvider).setPhoto(detail.id, name);
      _changed();
      if (mounted) SdToast.show(context, l10n.p360PhotoSaved);
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _printProfile(StudentDetail detail, String? yearLabel) async {
    final l10n = AppLocalizations.of(context);
    final academic = ref.read(academicControllerProvider);
    final includeCaste = _can('students.view_sensitive');
    final extra = await ref.read(extraFieldsProvider.future);
    final labels = await ref.read(allDivisionLabelsProvider.future);
    final head = await reportLetterhead(ref);
    if (!mounted) return;
    final data = studentProfileDataset(
      l10n,
      detail: detail,
      extraFields: extra,
      divisionLabels: labels,
      yearLabels: {for (final y in academic.years) y.id: y.label},
      yearLabel: yearLabel,
      includeCaste: includeCaste,
    );
    await showReportPdfPreview(context, data, head);
  }

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
    if (!_can('students.view_sensitive')) return;
    final value = await ref.read(studentRepositoryProvider).revealAadhaar(detail.id);
    if (!mounted) return;
    setState(() => _revealedAadhaar = value);
    SdToast.show(context, l10n.aadhaarRevealed);
  }

  void _edit(StudentDetail detail) {
    _remember();
    context.go('/students/${detail.id}/edit');
  }

  void _go(String route) {
    _remember();
    context.go(route);
  }

  // ================================================================== build

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detailAsync = ref.watch(studentDetailProvider(widget.studentId));
    return detailAsync.when(
      loading: () => const SdPage(children: [
        SdSkeleton(height: 160),
        SizedBox(height: SdSpace.lg),
        SdSkeleton(height: 44),
        SizedBox(height: SdSpace.lg),
        SdSkeleton(height: 240),
      ]),
      error: (e, _) => SdPage(children: [
        SdEmptyState(
          icon: Icons.error_outline,
          title: l10n.p360LoadFailed,
          message: '',
          action: SdButton(label: l10n.back, onPressed: () => context.go('/students')),
        ),
      ]),
      data: (detail) {
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
        return _profile(context, l10n, detail);
      },
    );
  }

  Widget _profile(BuildContext context, AppLocalizations l10n, StudentDetail detail) {
    final academic = ref.watch(academicControllerProvider);
    final modules = ref.watch(enabledModulesProvider);
    final labels = ref.watch(allDivisionLabelsProvider).valueOrNull ?? const <String, String>{};
    final years = profileYears(academic, detail);
    final yearId = (_yearId != null && years.any((y) => y.id == _yearId)) ? _yearId : defaultProfileYear(academic, detail);
    final year = years.where((y) => y.id == yearId).firstOrNull;
    final yearLabel = year?.label ?? '';
    final enrollment = enrollmentIn(detail, yearId);
    final classLabel = enrollment == null ? null : labels[enrollment.divisionId];
    final classLine = [
      if (classLabel != null) classLabel,
      if (enrollment?.rollNumber != null) l10n.rollShort(enrollment!.rollNumber!),
    ].join(' · ');
    final key = yearId == null ? null : (studentId: detail.id, yearId: yearId);

    final parts = [
      _Part.overview,
      _Part.personal,
      _Part.academic,
      _Part.documents,
      if (modules.contains('attendance')) _Part.attendance,
      if (modules.contains('fees')) _Part.fees,
      if (modules.contains('results')) _Part.results,
      if (modules.contains('certificates')) _Part.certificates,
      if (modules.contains('messages')) _Part.messages,
      _Part.history,
    ];
    final part = parts.contains(_part) ? _part : _Part.overview;

    return SdPage(
      children: [
        _TopBar(
          years: years,
          yearId: yearId,
          onBack: () => context.go('/students'),
          onYear: (id) => setState(() {
            _yearId = id;
            _remember();
          }),
          onEdit: _can('students.edit') ? () => _edit(detail) : null,
          menu: PopupMenuButton<String>(
            tooltip: l10n.p360More,
            onSelected: (v) {
              switch (v) {
                case 'pay':
                  _go('/fees/pay?student=${detail.id}');
                case 'certificate':
                  _go('/certificates/new?student=${detail.id}');
                case 'print':
                  _printProfile(detail, yearLabel.isEmpty ? null : yearLabel);
                case 'left':
                  _markLeft(detail);
                case 'delete':
                  _delete(detail);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'print', child: Text(l10n.p360PrintProfile)),
              if (modules.contains('fees') && _can('fees.collect') && detail.status == StudentStatus.active)
                PopupMenuItem(value: 'pay', child: Text(l10n.feeTakePayment)),
              if (modules.contains('certificates') && _can('certificates.issue'))
                PopupMenuItem(value: 'certificate', child: Text(l10n.p360MakeCertificate)),
              if (detail.status == StudentStatus.active && _can('students.edit'))
                PopupMenuItem(value: 'left', child: Text(l10n.studentMarkLeft)),
              if (_can('students.edit')) PopupMenuItem(value: 'delete', child: Text(l10n.studentDelete)),
            ],
          ),
        ),
        const SizedBox(height: SdSpace.md),
        _Header(
          detail: detail,
          photo: studentPhoto(ref.watch(startupStateProvider).mediaDir, detail.draft.photoFileName),
          classLine: classLine,
          yearLabel: yearLabel,
          photoBusy: _photoBusy,
          canCall: Platform.isAndroid && _contacts(l10n, detail).isNotEmpty,
          canMessage: _contacts(l10n, detail).isNotEmpty,
          onCall: () => _call(detail),
          onWhatsApp: () => _whatsApp(detail),
          onCopy: () => _copy(detail, classLine.isEmpty ? null : '$classLine ($yearLabel)'),
          onPhoto: ref.watch(startupStateProvider).mediaDir != null && _can('students.edit') ? () => _changePhoto(detail) : null,
          onPrint: () => _printProfile(detail, yearLabel.isEmpty ? null : yearLabel),
        ),
        const SizedBox(height: SdSpace.lg),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final pt in parts)
                Padding(
                  padding: const EdgeInsets.only(right: SdSpace.sm),
                  child: ChoiceChip(
                    avatar: Icon(_partIcon(pt), size: 18),
                    label: Text(_partLabel(l10n, pt)),
                    selected: pt == part,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _part = pt;
                      _remember();
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: SdSpace.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            fit: StackFit.passthrough,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey('$part|$yearId'),
            child: _partBody(context, l10n, part, detail, key, yearLabel, enrollment, labels, academic),
          ),
        ),
      ],
    );
  }

  IconData _partIcon(_Part p) => switch (p) {
        _Part.overview => Icons.dashboard_outlined,
        _Part.personal => Icons.person_outline,
        _Part.academic => Icons.badge_outlined,
        _Part.documents => Icons.folder_copy_outlined,
        _Part.attendance => Icons.fact_check_outlined,
        _Part.fees => Icons.currency_rupee,
        _Part.results => Icons.emoji_events_outlined,
        _Part.certificates => Icons.workspace_premium_outlined,
        _Part.messages => Icons.forum_outlined,
        _Part.history => Icons.timeline,
      };

  String _partLabel(AppLocalizations l10n, _Part p) => switch (p) {
        _Part.overview => l10n.p360TabOverview,
        _Part.personal => l10n.p360TabPersonal,
        _Part.academic => l10n.p360TabAcademic,
        _Part.documents => l10n.docTitle,
        _Part.attendance => l10n.navAttendance,
        _Part.fees => l10n.navFees,
        _Part.results => l10n.navResults,
        _Part.certificates => l10n.navCertificates,
        _Part.messages => l10n.navMessages,
        _Part.history => l10n.p360TabHistory,
      };

  Widget _partBody(
    BuildContext context,
    AppLocalizations l10n,
    _Part part,
    StudentDetail detail,
    StudentYearKey? key,
    String yearLabel,
    EnrollmentInfo? enrollment,
    Map<String, String> labels,
    AcademicSnapshot academic,
  ) {
    final modules = ref.watch(enabledModulesProvider);
    final VoidCallback? fix = _can('students.edit') ? () => _edit(detail) : null;
    final VoidCallback? issue =
        modules.contains('certificates') && _can('certificates.issue') ? () => _go('/certificates/new?student=${detail.id}') : null;
    // The register only covers classes of the active year.
    final activeId = academic.activeYear?.id;
    final VoidCallback? openAttendance = enrollment != null &&
            enrollment.academicYearId == activeId &&
            enrollment.status == EnrollmentStatus.active &&
            _can('attendance.mark')
        ? () => _go('/attendance/register?division=${enrollment.divisionId}&back=${Uri.encodeComponent('/students/${detail.id}')}')
        : null;
    final noYear = ProfileCard(
      icon: Icons.event_note_outlined,
      title: l10n.p360NoYearTitle,
      child: ProfileNote(icon: Icons.info_outline, text: l10n.p360NoYear),
    );

    switch (part) {
      case _Part.overview:
        return LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final leaving = detail.status == StudentStatus.left ? _leavingCard(l10n, detail) : null;
          final completeness = CompletenessCard(detail: detail, yearId: key?.yearId, onFix: fix);
          final fees = modules.contains('fees') && key != null ? FeesSummaryCard(yearKey: key, yearLabel: yearLabel) : null;
          final attendance = modules.contains('attendance') && key != null
              ? AttendanceSummaryCard(yearKey: key, yearLabel: yearLabel, onOpen: openAttendance)
              : null;
          final results = modules.contains('results') && key != null
              ? ResultsSummaryCard(yearKey: key, yearLabel: yearLabel, latestOnly: true)
              : null;
          final certs = modules.contains('certificates') ? CertificatesCard(studentId: detail.id, limit: 3, onIssue: issue) : null;
          final contacts = _contactsCard(l10n, detail);
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (leaving != null) leaving,
                completeness,
                if (fees != null) fees,
                if (attendance != null) attendance,
                if (results != null) results,
                if (certs != null) certs,
                contacts,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (leaving != null) leaving,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [completeness, if (attendance != null) attendance, if (results != null) results],
                    ),
                  ),
                  const SizedBox(width: SdSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [if (fees != null) fees, if (certs != null) certs, contacts],
                    ),
                  ),
                ],
              ),
            ],
          );
        });
      case _Part.personal:
        return _personal(l10n, detail);
      case _Part.academic:
        return _academic(l10n, detail, yearLabel, enrollment, labels);
      case _Part.documents:
        return StudentDocumentsSection(
          detail: detail,
          programId: academic.divisions.where((d) => d.id == enrollment?.divisionId).firstOrNull?.programId,
          classLine: enrollment == null ? null : labels[enrollment.divisionId],
        );
      case _Part.attendance:
        if (key == null) return noYear;
        return AttendanceSummaryCard(yearKey: key, yearLabel: yearLabel, onOpen: openAttendance);
      case _Part.fees:
        if (key == null) return noYear;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FeesSummaryCard(yearKey: key, yearLabel: yearLabel, showReceipts: true),
            if (_can('fees.collect') && detail.status == StudentStatus.active)
              Align(
                alignment: Alignment.centerLeft,
                child: SdButton(
                  label: l10n.feeTakePayment,
                  icon: Icons.add_card,
                  onPressed: () => _go('/fees/pay?student=${detail.id}'),
                ),
              ),
          ],
        );
      case _Part.results:
        if (key == null) return noYear;
        return ResultsSummaryCard(yearKey: key, yearLabel: yearLabel);
      case _Part.certificates:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CertificatesCard(studentId: detail.id),
            if (issue != null)
              Align(
                alignment: Alignment.centerLeft,
                child: SdButton(label: l10n.p360MakeCertificate, icon: Icons.add, onPressed: issue),
              ),
          ],
        );
      case _Part.messages:
        if (key == null) return noYear;
        return MessagesCard(yearKey: key, yearLabel: yearLabel);
      case _Part.history:
        return _history(l10n, detail, labels, academic);
    }
  }

  Widget _leavingCard(AppLocalizations l10n, StudentDetail detail) => ProfileCard(
        icon: Icons.logout,
        title: l10n.sectionLeaving,
        child: Column(children: [
          InfoRow(label: l10n.fieldLeavingDate, value: _fmt(detail.leavingDate)),
          InfoRow(label: l10n.fieldLeavingReason, value: detail.leavingReason),
        ]),
      );

  Widget _contactsCard(AppLocalizations l10n, StudentDetail detail) {
    final contacts = _contacts(l10n, detail);
    return ProfileCard(
      icon: Icons.contact_phone_outlined,
      title: l10n.p360Contacts,
      child: contacts.isEmpty
          ? ProfileNote(icon: Icons.phone_disabled_outlined, text: l10n.p360NoContacts)
          : Column(
              children: [
                for (final (who, number) in contacts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(who),
                    subtitle: Text(number),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (Platform.isAndroid)
                          IconButton(
                            tooltip: l10n.p360Call,
                            icon: const Icon(Icons.call_outlined),
                            onPressed: () => launchUrl(Uri(scheme: 'tel', path: number)),
                          ),
                        IconButton(
                          tooltip: l10n.p360WhatsApp,
                          icon: const Icon(Icons.chat_outlined),
                          onPressed: () async {
                            final ok = await openWhatsApp(mobile: number, text: '');
                            if (mounted) SdToast.show(context, ok ? l10n.p360WhatsAppOpened : l10n.msgOpenFailed);
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _personal(AppLocalizations l10n, StudentDetail detail) {
    final d = detail.draft;
    final theme = Theme.of(context);
    final canSeeSensitive = _can('students.view_sensitive');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileCard(
          icon: Icons.person_outline,
          title: l10n.sectionPersonal,
          child: Column(children: [
            InfoRow(label: l10n.p360Name, value: d.fullName),
            if (d.altName.isNotEmpty) InfoRow(label: l10n.p360AltName, value: d.altName),
            InfoRow(label: l10n.fieldGender, value: d.gender),
            InfoRow(label: l10n.fieldDateOfBirth, value: _fmt(d.dateOfBirth)),
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
        ),
        ProfileCard(
          icon: Icons.family_restroom,
          title: l10n.sectionGuardians,
          child: detail.guardians.isEmpty
              ? ProfileNote(icon: Icons.info_outline, text: l10n.p360NoGuardians)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < detail.guardians.length; i++) ...[
                      if (i > 0) const Divider(height: SdSpace.lg),
                      Row(children: [
                        Expanded(
                          child: Text(
                            '${detail.guardians[i].name} (${detail.guardians[i].relation})',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (detail.guardians[i].isPrimary)
                          StatusPill(text: l10n.fieldPrimaryContact, color: theme.colorScheme.primary),
                      ]),
                      InfoRow(label: l10n.fieldMobile, value: detail.guardians[i].mobile),
                      if (detail.guardians[i].altMobile != null)
                        InfoRow(label: l10n.fieldAltMobile, value: detail.guardians[i].altMobile),
                      if (detail.guardians[i].email != null) InfoRow(label: l10n.fieldEmail, value: detail.guardians[i].email),
                      if (detail.guardians[i].occupation != null)
                        InfoRow(label: l10n.fieldOccupation, value: detail.guardians[i].occupation),
                    ],
                  ],
                ),
        ),
        ProfileCard(
          icon: Icons.favorite_outline,
          title: l10n.sectionHealth,
          child: Column(children: [
            InfoRow(label: l10n.fieldBloodGroup, value: d.bloodGroup),
            InfoRow(label: l10n.fieldHeightPick, value: StudentChoices.heightLabel(d.heightCm)),
            InfoRow(label: l10n.fieldWeightPick, value: StudentChoices.weightLabel(d.weightKg)),
            InfoRow(label: l10n.fieldMeasuredOn, value: _fmt(d.measuredOn)),
          ]),
        ),
        if (d.notes.isNotEmpty)
          ProfileCard(icon: Icons.notes, title: l10n.sectionNotes, child: Text(d.notes)),
      ],
    );
  }

  Widget _academic(
    AppLocalizations l10n,
    StudentDetail detail,
    String yearLabel,
    EnrollmentInfo? enrollment,
    Map<String, String> labels,
  ) {
    final d = detail.draft;
    final canSeeSensitive = _can('students.view_sensitive');
    final extra = ref.watch(extraFieldsProvider).valueOrNull ?? const <ExtraFieldDefinition>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileCard(
          icon: Icons.school_outlined,
          title: l10n.p360Admission,
          child: Column(children: [
            InfoRow(label: l10n.p360StudentCode, value: detail.displayCode),
            InfoRow(label: l10n.academicYearShort, value: yearLabel),
            InfoRow(label: l10n.fieldClass, value: enrollment == null ? null : labels[enrollment.divisionId]),
            InfoRow(label: l10n.fieldRollNumber, value: enrollment?.rollNumber?.toString()),
            InfoRow(label: l10n.p360Status, value: studentStatusLabel(l10n, detail.status)),
            InfoRow(label: l10n.fieldAdmissionDate, value: _fmt(d.admissionDate)),
            InfoRow(label: l10n.fieldPreviousSchool, value: d.previousSchool),
          ]),
        ),
        ProfileCard(
          icon: Icons.badge_outlined,
          title: l10n.sectionIdentifiers,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final type in IdentifierType.values)
                InfoRow(
                  label: identifierLabel(l10n, type),
                  value: type == IdentifierType.aadhaar && _revealedAadhaar != null ? _revealedAadhaar : detail.identifier(type),
                  trailing: type == IdentifierType.aadhaar &&
                          detail.identifier(type) != null &&
                          _revealedAadhaar == null &&
                          canSeeSensitive
                      ? TextButton(onPressed: () => _reveal(detail), child: Text(l10n.aadhaarReveal))
                      : null,
                ),
              if (detail.identifier(IdentifierType.aadhaar) != null && _revealedAadhaar == null)
                Padding(
                  padding: const EdgeInsets.only(top: SdSpace.xs),
                  child: Text(
                    l10n.p360AadhaarHidden,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SdColors.of(context).textMuted),
                  ),
                ),
            ],
          ),
        ),
        ProfileCard(
          icon: Icons.tune,
          title: l10n.sectionExtra,
          action: TextButton(
            onPressed: () => _go('/settings/student-fields'),
            child: Text(l10n.p360ManageFields),
          ),
          child: extra.isEmpty
              ? ProfileNote(icon: Icons.info_outline, text: l10n.p360NoExtraFields)
              : Column(children: [
                  for (final f in extra) InfoRow(label: f.label, value: _extraDisplay(l10n, f, d.extra[f.key])),
                ]),
        ),
      ],
    );
  }

  Widget _history(AppLocalizations l10n, StudentDetail detail, Map<String, String> labels, AcademicSnapshot academic) {
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final yearLabels = {for (final y in academic.years) y.id: y.label};
    return ProfileCard(
      icon: Icons.timeline,
      title: l10n.sectionHistory,
      child: detail.enrollments.isEmpty
          ? ProfileNote(icon: Icons.info_outline, text: l10n.placementNone)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < detail.enrollments.length; i++)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Column(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == 0 ? theme.colorScheme.primary : sd.border,
                                ),
                              ),
                              if (i < detail.enrollments.length - 1)
                                Expanded(child: Container(width: 2, color: sd.border)),
                            ],
                          ),
                        ),
                        const SizedBox(width: SdSpace.sm),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: SdSpace.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  yearLabels[detail.enrollments[i].academicYearId] ?? '',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    labels[detail.enrollments[i].divisionId] ?? '',
                                    if (detail.enrollments[i].rollNumber != null)
                                      l10n.rollShort(detail.enrollments[i].rollNumber!),
                                    enrollmentStatusLabel(l10n, detail.enrollments[i].status),
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  style: theme.textTheme.bodyMedium?.copyWith(color: sd.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(l10n.p360HistoryNote, style: theme.textTheme.bodySmall?.copyWith(color: sd.textMuted)),
              ],
            ),
    );
  }

  static String? _fmt(DateTime? d) => d == null ? null : DateFormat('d MMM y').format(d);

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

// =================================================================== parts

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.years,
    required this.yearId,
    required this.onBack,
    required this.onYear,
    required this.onEdit,
    required this.menu,
  });

  final List<AcademicYear> years;
  final String? yearId;
  final VoidCallback onBack;
  final ValueChanged<String> onYear;
  final VoidCallback? onEdit;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: onBack),
        const Spacer(),
        if (years.length > 1)
          Tooltip(
            message: l10n.p360ChooseYear,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: yearId,
                borderRadius: BorderRadius.circular(SdRadius.md),
                icon: const Icon(Icons.expand_more),
                items: [
                  for (final y in years)
                    DropdownMenuItem(
                      value: y.id,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.calendar_today_outlined, size: 16),
                        const SizedBox(width: SdSpace.sm),
                        Text(y.label),
                      ]),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onYear(v);
                },
              ),
            ),
          ),
        const SizedBox(width: SdSpace.sm),
        if (onEdit != null)
          SdButton(
            label: l10n.studentEditTitle,
            icon: Icons.edit_outlined,
            variant: SdButtonVariant.secondary,
            onPressed: onEdit,
          ),
        menu,
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.photo,
    required this.classLine,
    required this.yearLabel,
    required this.photoBusy,
    required this.canCall,
    required this.canMessage,
    required this.onCall,
    required this.onWhatsApp,
    required this.onCopy,
    required this.onPhoto,
    required this.onPrint,
  });

  final StudentDetail detail;
  final File? photo;
  final String classLine;
  final String yearLabel;
  final bool photoBusy;
  final bool canCall;
  final bool canMessage;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onCopy;
  final VoidCallback? onPhoto;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final primary = theme.colorScheme.primary;
    final d = detail.draft;
    final compact = MediaQuery.sizeOf(context).width < SdBreakpoints.compact;
    final gr = detail.identifier(IdentifierType.grNumber);
    final statusColor = switch (detail.status) {
      StudentStatus.active => sd.present,
      StudentStatus.left => sd.absent,
      StudentStatus.alumni => sd.info,
      StudentStatus.archived => sd.textMuted,
    };

    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primary.withValues(alpha: 0.35), width: 2)),
          child: StudentAvatar(name: d.fullName, photo: photo, size: compact ? 72 : 88),
        ),
        if (onPhoto != null)
          Positioned(
            right: -4,
            bottom: -4,
            child: Material(
              color: theme.colorScheme.surface,
              shape: CircleBorder(side: BorderSide(color: sd.border)),
              child: IconButton(
                tooltip: l10n.p360ChangePhoto,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: photoBusy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_camera_outlined),
                onPressed: photoBusy ? null : onPhoto,
              ),
            ),
          ),
      ],
    );

    final meta = <String>[
      detail.displayCode,
      if (gr != null) '${l10n.idGr} $gr',
      if (classLine.isNotEmpty) classLine,
    ];

    final info = Column(
      crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (yearLabel.isNotEmpty)
          Text(
            yearLabel.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: primary, letterSpacing: 1.2, fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 2),
        Text(
          d.fullName,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (d.altName.isNotEmpty)
          Text(d.altName, textAlign: compact ? TextAlign.center : TextAlign.start, style: theme.textTheme.titleMedium),
        const SizedBox(height: SdSpace.xs),
        Text(
          meta.join(' · '),
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.bodyMedium?.copyWith(color: sd.textMuted),
        ),
        const SizedBox(height: SdSpace.sm),
        StatusPill(text: studentStatusLabel(l10n, detail.status), color: statusColor),
      ],
    );

    final actions = Wrap(
      spacing: SdSpace.sm,
      runSpacing: SdSpace.sm,
      alignment: compact ? WrapAlignment.center : WrapAlignment.start,
      children: [
        if (canCall)
          SdButton(label: l10n.p360Call, icon: Icons.call_outlined, onPressed: onCall),
        if (canMessage)
          SdButton(
            label: l10n.p360WhatsApp,
            icon: Icons.chat_outlined,
            variant: canCall ? SdButtonVariant.secondary : SdButtonVariant.primary,
            onPressed: onWhatsApp,
          ),
        SdButton(label: l10n.p360CopyDetails, icon: Icons.copy_outlined, variant: SdButtonVariant.secondary, onPressed: onCopy),
        SdButton(label: l10n.reportPrint, icon: Icons.print_outlined, variant: SdButtonVariant.secondary, onPressed: onPrint),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(SdRadius.md),
        border: Border.all(color: primary.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(SdSpace.xl),
      child: compact
          ? Column(children: [avatar, const SizedBox(height: SdSpace.md), info, const SizedBox(height: SdSpace.lg), actions])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [avatar, const SizedBox(width: SdSpace.xl), Expanded(child: info)]),
                const SizedBox(height: SdSpace.lg),
                actions,
              ],
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
