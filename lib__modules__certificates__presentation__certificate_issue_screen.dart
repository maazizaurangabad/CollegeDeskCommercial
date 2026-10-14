import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../students/application/students_providers.dart';
import '../../students/domain/student_models.dart';
import '../../students/presentation/student_labels.dart';
import '../application/certificates_providers.dart';
import '../domain/certificate_models.dart';

/// Choose a student and a certificate, check the filled-in details, issue.
class CertificateIssueScreen extends ConsumerStatefulWidget {
  const CertificateIssueScreen({super.key, this.studentId, this.kind});

  final String? studentId;
  final CertificateKind? kind;

  @override
  ConsumerState<CertificateIssueScreen> createState() => _CertificateIssueScreenState();
}

class _CertificateIssueScreenState extends ConsumerState<CertificateIssueScreen> {
  late CertificateKind _kind = widget.kind ?? CertificateKind.bonafide;
  String? _studentId;
  Map<String, String>? _fields;
  final Map<String, TextEditingController> _controllers = {};
  bool _officeCopy = true;
  bool _markLeft = true;
  bool _hasLc = false;
  bool _busy = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.studentId != null) WidgetsBinding.instance.addPostFrameCallback((_) => _choose(widget.studentId!));
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choose(String studentId) async {
    setState(() => _busy = true);
    final labels = await ref.read(academicRepositoryProvider).divisionLabels();
    final fields = await ref.read(certificateRepositoryProvider).prefill(studentId, divisionLabels: labels);
    final existing = await ref.read(certificateRepositoryProvider).list(kind: CertificateKind.leaving, studentId: studentId);
    if (!mounted) return;
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers
      ..clear()
      ..addAll({for (final e in fields.entries) e.key: TextEditingController(text: e.value)});
    setState(() {
      _studentId = studentId;
      _fields = fields;
      _hasLc = existing.any((c) => c.status == CertificateStatus.issued && !c.isDuplicate);
      _busy = false;
    });
  }

  Map<String, String> get _values => {for (final e in _controllers.entries) e.key: e.value.text.trim()};

  List<(String, String)> _fieldsFor(AppLocalizations l10n) {
    final common = [
      (CertField.name, l10n.cfName),
      (CertField.gender, l10n.cfGender),
      (CertField.grNumber, l10n.cfGr),
    ];
    return switch (_kind) {
      CertificateKind.bonafide => [
          ...common,
          (CertField.className, l10n.cfClass),
          (CertField.academicYear, l10n.cfYear),
          (CertField.dateOfBirth, l10n.cfDob),
          (CertField.dateOfBirthWords, l10n.cfDobWords),
          (CertField.purpose, l10n.cfPurpose),
          (CertField.remarks, l10n.cfRemarks),
        ],
      CertificateKind.character => [
          ...common,
          (CertField.studyingSince, l10n.cfStudying),
          (CertField.conduct, l10n.cfConduct),
          (CertField.remarks, l10n.cfRemarks),
        ],
      CertificateKind.noc => [
          ...common,
          (CertField.className, l10n.cfClass),
          (CertField.academicYear, l10n.cfYear),
          (CertField.purpose, l10n.cfNocPurpose),
          (CertField.remarks, l10n.cfRemarks),
        ],
      CertificateKind.noDues => [
          ...common,
          (CertField.className, l10n.cfClass),
          (CertField.academicYear, l10n.cfYear),
          (CertField.purpose, l10n.cfPurpose),
          (CertField.remarks, l10n.cfRemarks),
        ],
      CertificateKind.leaving => [
          (CertField.name, l10n.cfName),
          (CertField.grNumber, l10n.cfGr),
          (CertField.motherName, l10n.cfMother),
          (CertField.nationality, l10n.cfNationality),
          (CertField.motherTongue, l10n.cfMotherTongue),
          (CertField.religion, l10n.cfReligion),
          (CertField.casteSubcaste, l10n.cfCaste),
          (CertField.placeOfBirth, l10n.cfPlaceOfBirth),
          (CertField.dateOfBirth, l10n.cfDob),
          (CertField.dateOfBirthWords, l10n.cfDobWords),
          (CertField.previousSchool, l10n.cfPrevious),
          (CertField.admissionDateClass, l10n.cfAdmission),
          (CertField.progress, l10n.cfProgress),
          (CertField.conduct, l10n.cfConduct),
          (CertField.leavingDate, l10n.cfLeavingDate),
          (CertField.studyingSince, l10n.cfStudying),
          (CertField.leavingReason, l10n.cfReason),
          (CertField.remarks, l10n.cfRemarks),
        ],
    };
  }

  Future<void> _preview() async {
    final bytes = await certificatePdf(
      ref,
      kind: _kind,
      fields: _values,
      serialLabel: '${_kind.prefix}/DRAFT',
      issuedOn: DateTime.now(),
      duplicate: _kind == CertificateKind.leaving && _hasLc,
      officeCopy: _officeCopy,
    );
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).certPreview)),
        body: PdfPreview(
          build: (_) => bytes,
          allowPrinting: false,
          allowSharing: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
        ),
      ),
    ));
  }

  Future<void> _issue() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final values = {..._values, 'office_copy': '$_officeCopy'};
      final record = await ref.read(certificateRepositoryProvider).issue(
            kind: _kind,
            studentId: _studentId!,
            fields: values,
            academicYearLabel: ref.read(academicControllerProvider).activeYear?.label ??
                (values[CertField.academicYear] ?? ''),
            markLeft: _kind == CertificateKind.leaving && _markLeft,
          );
      ref.read(certificatesRevisionProvider.notifier).state++;
      if (_kind == CertificateKind.leaving && _markLeft) ref.read(studentsRevisionProvider.notifier).state++;
      if (!mounted) return;
      SdToast.show(context, l10n.certIssued);
      context.go('/certificates/view/${record.id}');
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        SdToast.show(context, l10n.saveFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final academic = ref.watch(academicControllerProvider);

    return SdPage(
      children: [
        Row(children: [
          IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/certificates')),
          const SizedBox(width: SdSpace.xs),
          Expanded(child: Text(l10n.certIssue, style: theme.textTheme.headlineSmall)),
        ]),
        const SizedBox(height: SdSpace.lg),
        SdSelectField<CertificateKind>(
          label: l10n.certChooseType,
          value: _kind,
          options: [for (final k in CertificateKind.values) (k, certificateTitle(l10n, k))],
          onChanged: (k) => setState(() => _kind = k ?? _kind),
        ),
        if (_studentId == null) ...[
          SdSection(
            title: l10n.certChooseStudent,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SdTextField(
                hint: l10n.certSearchStudent,
                prefixIcon: Icons.search,
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: SdSpace.md),
              if (_query.length >= 2)
                FutureBuilder<List<StudentListItem>>(
                  future: ref.read(studentRepositoryProvider).list(
                        query: _query,
                        academicYearId: academic.activeYear?.id,
                        limit: 20,
                      ),
                  builder: (context, snapshot) {
                    final items = snapshot.data ?? const <StudentListItem>[];
                    return SdCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (final s in items)
                          ListTile(
                            title: Text(s.fullName),
                            subtitle: Text([s.displayCode, placementName(academic, s.divisionId) ?? '']
                                .where((x) => x.isNotEmpty)
                                .join(' · ')),
                            trailing: s.status == StudentStatus.active
                                ? null
                                : StatusPill(text: studentStatusLabel(l10n, s.status), color: SdColors.of(context).textMuted),
                            onTap: _busy ? null : () => _choose(s.id),
                          ),
                      ]),
                    );
                  },
                ),
            ]),
          ),
        ] else if (_fields != null) ...[
          SdSection(
            title: l10n.certDetails,
            trailing: SdButton(
              label: l10n.certChooseStudent,
              variant: SdButtonVariant.text,
              onPressed: () => setState(() {
                _studentId = null;
                _fields = null;
              }),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l10n.certDetailsHint, style: theme.textTheme.bodySmall),
              const SizedBox(height: SdSpace.md),
              if (_kind == CertificateKind.leaving && _hasLc)
                Padding(
                  padding: const EdgeInsets.only(bottom: SdSpace.md),
                  child: Text(l10n.certDuplicateNote, style: theme.textTheme.bodySmall?.copyWith(color: SdColors.of(context).leave)),
                ),
              SdCard(
                child: Column(children: [
                  for (final (key, label) in _fieldsFor(l10n))
                    Padding(
                      padding: const EdgeInsets.only(bottom: SdSpace.md),
                      child: TextField(
                        controller: _controllers[key] ??= TextEditingController(),
                        maxLines: key == CertField.remarks ? 2 : 1,
                        decoration: InputDecoration(labelText: label),
                      ),
                    ),
                ]),
              ),
              if (_kind == CertificateKind.bonafide || _kind == CertificateKind.character)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.certOfficeCopy),
                  value: _officeCopy,
                  onChanged: (v) => setState(() => _officeCopy = v),
                ),
              if (_kind == CertificateKind.leaving && !_hasLc)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.certMarkLeft),
                  value: _markLeft,
                  onChanged: (v) => setState(() => _markLeft = v),
                ),
              const SizedBox(height: SdSpace.lg),
              Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
                SdButton(
                  label: l10n.certPreview,
                  icon: Icons.visibility_outlined,
                  variant: SdButtonVariant.secondary,
                  onPressed: _busy ? null : _preview,
                ),
                SdButton(label: l10n.certIssueNow, icon: Icons.check, onPressed: _busy ? null : _issue),
              ]),
              const SizedBox(height: SdSpace.xxl),
            ]),
          ),
        ],
      ],
    );
  }
}
