import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_models.dart';
import '../domain/student_models.dart';

String identifierLabel(AppLocalizations l10n, IdentifierType type) => switch (type) {
      IdentifierType.grNumber => l10n.idGr,
      IdentifierType.pen => l10n.idPen,
      IdentifierType.apaar => l10n.idApaar,
      IdentifierType.saralId => l10n.idSaral,
      IdentifierType.admissionNumber => l10n.idAdmission,
      IdentifierType.aadhaar => l10n.idAadhaar,
    };

String studentStatusLabel(AppLocalizations l10n, StudentStatus status) => switch (status) {
      StudentStatus.active => l10n.statusActive,
      StudentStatus.left => l10n.statusLeft,
      StudentStatus.alumni => l10n.statusAlumni,
      StudentStatus.archived => l10n.statusArchived,
    };

String enrollmentStatusLabel(AppLocalizations l10n, EnrollmentStatus status) => switch (status) {
      EnrollmentStatus.active => l10n.enrollActive,
      EnrollmentStatus.left => l10n.enrollLeft,
      EnrollmentStatus.promoted => l10n.enrollPromoted,
      EnrollmentStatus.detained => l10n.enrollDetained,
      EnrollmentStatus.graduated => l10n.enrollGraduated,
      EnrollmentStatus.transferred => l10n.enrollTransferred,
    };

String duplicateReasonLabel(AppLocalizations l10n, DuplicateReason reason) => switch (reason) {
      DuplicateReason.sameNameAndBirthDate => l10n.dupSameNameDob,
      DuplicateReason.sameIdentifier => l10n.dupSameId,
      DuplicateReason.sameMobileSimilarName => l10n.dupSameMobile,
    };

String studentErrorMessage(AppLocalizations l10n, Object error) {
  if (error is! StudentValidationException) return l10n.saveFailed;
  return switch (error.issue) {
    StudentIssue.nameRequired => l10n.issueNameRequired,
    StudentIssue.invalidAadhaar => l10n.issueInvalidAadhaar,
    StudentIssue.invalidMobile => '${l10n.fieldMobile}: ${error.detail ?? ''}',
    StudentIssue.duplicateIdentifier => l10n.issueDuplicateIdentifier,
    StudentIssue.duplicateRoll => l10n.issueDuplicateRoll,
    StudentIssue.divisionNotInActiveYear => l10n.issueDivisionNotActive,
    StudentIssue.requiredFieldMissing => '${l10n.issueRequiredExtra} (${error.detail ?? ''})',
    StudentIssue.notFound => l10n.studentNotFound,
  };
}

/// "11th Science A" for a division in the academic snapshot.
String? placementName(AcademicSnapshot academic, String? divisionId, {AppLocalizations? l10n}) {
  if (divisionId == null) return null;
  final division = academic.divisions.where((d) => d.id == divisionId).firstOrNull;
  if (division == null) return null;
  final program = academic.programs.where((p) => p.id == division.programId).firstOrNull;
  return '${program?.name ?? ''} ${division.name}'.trim();
}

File? studentPhoto(Directory? mediaDir, String? fileName) {
  if (mediaDir == null || fileName == null) return null;
  final file = File(p.join(mediaDir.path, fileName));
  return file.existsSync() ? file : null;
}

/// Round photo, or initials when there is no photo.
class StudentAvatar extends StatelessWidget {
  const StudentAvatar({super.key, required this.name, this.photo, this.size = 40});

  final String name;
  final File? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final sd = SdColors.of(context);
    final parts = name.split(' ').where((s) => s.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.length == 1 ? parts.first[0] : parts.first[0] + parts.last[0]).toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: sd.subtleFill,
      backgroundImage: photo == null ? null : FileImage(photo!),
      child: photo == null
          ? Text(initials, style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w600, color: sd.textMuted))
          : null,
    );
  }
}

/// A small coloured label such as "Left".
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SdRadius.pill),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }
}

/// Label and value on one line inside a profile section. An empty value
/// shows "Not recorded".
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.trailing});

  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = value == null || value!.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SdSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: theme.textTheme.bodySmall)),
          const SizedBox(width: SdSpace.md),
          Expanded(
            child: Text(
              empty ? AppLocalizations.of(context).p360NotRecorded : value!,
              style: theme.textTheme.bodyMedium?.copyWith(color: empty ? SdColors.of(context).textMuted : null),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
