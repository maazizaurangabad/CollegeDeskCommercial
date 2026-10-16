import 'package:intl/intl.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/reporting/report_dataset.dart';
import '../domain/student_models.dart';

/// The student profile as a printable report: one row per detail, grouped
/// by section. Drawn by the shared report engine (letterhead, fonts,
/// preview). Aadhaar appears only in its masked form, as on screen.
ReportDataset studentProfileDataset(
  AppLocalizations l10n, {
  required StudentDetail detail,
  required List<ExtraFieldDefinition> extraFields,
  required Map<String, String> divisionLabels,
  required Map<String, String> yearLabels,
  String? yearLabel,
  bool includeCaste = true,
}) {
  final dates = DateFormat('d MMM y');
  String date(DateTime? d) => d == null ? '' : dates.format(d);
  final d = detail.draft;
  final rows = <ReportRow>[];

  void section(String title, List<(String, String?)> items) {
    rows.add(ReportRow.group(title));
    for (final (label, value) in items) {
      final v = (value ?? '').trim();
      rows.add(ReportRow([label, v.isEmpty ? l10n.p360NotRecorded : v]));
    }
  }

  section(l10n.sectionPersonal, [
    (l10n.p360Name, d.fullName),
    if (d.altName.isNotEmpty) (l10n.p360AltName, d.altName),
    (l10n.fieldGender, d.gender),
    (l10n.fieldDateOfBirth, date(d.dateOfBirth)),
    (l10n.fieldPlaceOfBirth, d.placeOfBirth),
    (l10n.fieldNationality, d.nationality),
    (l10n.fieldMotherTongue, d.motherTongue),
    (l10n.fieldCategory, d.category),
    if (includeCaste) ...[(l10n.fieldCaste, d.caste), (l10n.fieldSubCaste, d.subCaste)],
    (l10n.fieldBloodGroup, d.bloodGroup),
    (l10n.fieldAddress, d.address),
  ]);

  rows.add(ReportRow.group(l10n.sectionGuardians));
  if (detail.guardians.isEmpty) rows.add(ReportRow([l10n.sectionGuardians, l10n.p360NotRecorded]));
  for (final g in detail.guardians) {
    rows.add(ReportRow([
      '${g.relation}${g.isPrimary ? ' (${l10n.fieldPrimaryContact})' : ''}',
      [g.name, if ((g.mobile ?? '').isNotEmpty) g.mobile!, if ((g.altMobile ?? '').isNotEmpty) g.altMobile!].join(' · '),
    ]));
  }

  section(l10n.p360TabAcademic, [
    (l10n.p360StudentCode, detail.displayCode),
    for (final type in IdentifierType.values) (_idLabel(l10n, type), detail.identifier(type)),
    (l10n.fieldAdmissionDate, date(d.admissionDate)),
    (l10n.fieldPreviousSchool, d.previousSchool),
    for (final f in extraFields) (f.label, _extraText(l10n, f, d.extra[f.key])),
  ]);

  if (detail.enrollments.isNotEmpty) {
    rows.add(ReportRow.group(l10n.sectionHistory));
    for (final e in detail.enrollments) {
      rows.add(ReportRow([
        yearLabels[e.academicYearId] ?? '',
        [divisionLabels[e.divisionId] ?? '', if (e.rollNumber != null) l10n.rollShort(e.rollNumber!)]
            .where((s) => s.isNotEmpty)
            .join(' · '),
      ]));
    }
  }

  final subtitle = [
    detail.displayCode,
    if (detail.identifier(IdentifierType.grNumber) case final gr?) '${l10n.idGr} $gr',
    if (yearLabel != null) yearLabel,
  ];

  return ReportDataset(
    title: '${l10n.p360PdfTitle}: ${d.fullName}',
    subtitle: [subtitle.join(' · ')],
    columns: [
      ReportColumn(l10n.p360PdfDetail, flex: 2),
      ReportColumn(l10n.p360PdfValue, flex: 3),
    ],
    rows: rows,
    fileName: 'student-profile-${detail.displayCode}',
    fontSize: 10,
    notes: [l10n.p360PdfNote],
  );
}

String _idLabel(AppLocalizations l10n, IdentifierType type) => switch (type) {
      IdentifierType.grNumber => l10n.idGr,
      IdentifierType.pen => l10n.idPen,
      IdentifierType.apaar => l10n.idApaar,
      IdentifierType.saralId => l10n.idSaral,
      IdentifierType.admissionNumber => l10n.idAdmission,
      IdentifierType.aadhaar => l10n.idAadhaar,
    };

/// An own field's value as shown to people (yes/no, dates).
String? _extraText(AppLocalizations l10n, ExtraFieldDefinition f, String? value) {
  if (value == null || value.isEmpty) return null;
  if (f.type == 'yesNo') return value == 'true' ? l10n.yes : l10n.no;
  if (f.type == 'date') {
    final parsed = DateTime.tryParse(value);
    return parsed == null ? value : DateFormat('d MMM y').format(parsed);
  }
  return value;
}
