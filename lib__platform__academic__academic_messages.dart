import '../../l10n/gen/app_localizations.dart';
import 'academic_models.dart';

/// Turns a refused academic change into a message for the user.
String academicErrorMessage(AppLocalizations l10n, Object error) {
  if (error is! AcademicValidationException) return l10n.saveFailed;
  switch (error.issue) {
    case AcademicIssue.emptyName:
      return l10n.issueEmptyName;
    case AcademicIssue.duplicateYear:
      return l10n.issueDuplicateYear;
    case AcademicIssue.duplicateProgram:
    case AcademicIssue.duplicateDivision:
      return l10n.issueDuplicateName;
    case AcademicIssue.endBeforeStart:
      return l10n.issueEndBeforeStart;
    case AcademicIssue.programHasDivisions:
      return l10n.issueProgramHasDivisions;
    case AcademicIssue.divisionHasStudents:
      return l10n.issueDivisionHasStudents;
    case AcademicIssue.cannotCloseActiveYear:
      return l10n.issueCannotCloseActiveYear;
    case AcademicIssue.yearIsClosed:
      return l10n.issueYearIsClosed;
    case AcademicIssue.notFound:
      return l10n.issueNotFound;
  }
}
