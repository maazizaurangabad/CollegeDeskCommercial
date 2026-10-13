import '../../../l10n/gen/app_localizations.dart';
import '../domain/student_models.dart';
import 'import_fields.dart';
import 'import_planner.dart';

String importFieldLabel(AppLocalizations l10n, ImportField f) => switch (f) {
      ImportField.ignore => l10n.fieldIgnore,
      ImportField.serialNo => l10n.fieldSerialNo,
      ImportField.fullName => l10n.fieldFullName,
      ImportField.firstName => l10n.fieldFirstName,
      ImportField.middleName => l10n.fieldMiddleName,
      ImportField.lastName => l10n.fieldLastName,
      ImportField.altName => l10n.fieldAltName,
      ImportField.gender => l10n.fieldGender,
      ImportField.dateOfBirth => l10n.fieldDateOfBirth,
      ImportField.placeOfBirth => l10n.fieldPlaceOfBirth,
      ImportField.nationality => l10n.fieldNationality,
      ImportField.motherTongue => l10n.fieldMotherTongue,
      ImportField.category => l10n.fieldCategory,
      ImportField.caste => l10n.fieldCaste,
      ImportField.subCaste => l10n.fieldSubCaste,
      ImportField.bloodGroup => l10n.fieldBloodGroup,
      ImportField.heightCm => l10n.fieldHeight,
      ImportField.weightKg => l10n.fieldWeight,
      ImportField.address => l10n.fieldAddress,
      ImportField.admissionDate => l10n.fieldAdmissionDate,
      ImportField.previousSchool => l10n.fieldPreviousSchool,
      ImportField.grNumber => l10n.idGr,
      ImportField.pen => l10n.idPen,
      ImportField.apaar => l10n.idApaar,
      ImportField.saralId => l10n.idSaral,
      ImportField.admissionNumber => l10n.idAdmission,
      ImportField.aadhaar => l10n.idAadhaar,
      ImportField.className => l10n.fieldClass,
      ImportField.divisionName => l10n.fieldDivision,
      ImportField.rollNumber => l10n.fieldRollNumber,
      ImportField.fatherName => l10n.fieldFatherName,
      ImportField.motherName => l10n.fieldMotherName,
      ImportField.guardianName => l10n.fieldGuardianName,
      ImportField.mobile => l10n.fieldMobile,
      ImportField.altMobile => l10n.fieldAltMobile,
      ImportField.email => l10n.fieldEmail,
      ImportField.notes => l10n.fieldNotes,
    };

/// Every choice for a column: the built-in fields, then the institution's own.
List<(String, String)> mappingOptions(AppLocalizations l10n, List<ExtraFieldDefinition> extra) => [
      for (final f in ImportField.values) (fieldId(f), importFieldLabel(l10n, f)),
      for (final e in extra) (extraId(e.key), e.label),
    ];

String rowIssueLabel(AppLocalizations l10n, RowIssue issue) {
  final base = switch (issue.code) {
    RowIssueCode.missingName => l10n.issueMissingName,
    RowIssueCode.badDate => l10n.issueBadDate,
    RowIssueCode.badNumber => l10n.issueBadNumber,
    RowIssueCode.badBloodGroup => l10n.issueBadBloodGroup,
    RowIssueCode.invalidAadhaar => l10n.issueInvalidAadhaarRow,
    RowIssueCode.invalidMobile => l10n.issueInvalidMobileRow,
    RowIssueCode.duplicateInFile => l10n.issueDuplicateInFile,
    RowIssueCode.duplicateRoll => l10n.issueDuplicateRollRow,
    RowIssueCode.notPlaced => l10n.issueNotPlaced,
    RowIssueCode.willCreatePlacement => l10n.issueWillCreate,
    RowIssueCode.alreadyExists => l10n.issueAlreadyExists,
    RowIssueCode.possibleDuplicate => l10n.issuePossibleDuplicate,
    RowIssueCode.aadhaarTaken => l10n.issueAadhaarTaken,
    RowIssueCode.requiredExtraMissing => l10n.issueRequiredExtraRow,
    RowIssueCode.badChoice => l10n.issueBadChoice,
  };
  return issue.detail == null || issue.code == RowIssueCode.alreadyExists ? base : '$base (${issue.detail})';
}
