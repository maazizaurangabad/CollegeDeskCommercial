import 'package:flutter/foundation.dart';

/// Official numbers a student can have. Each is unique within an institution.
enum IdentifierType {
  grNumber('gr'),
  pen('pen'),
  apaar('apaar'),
  saralId('saral'),
  admissionNumber('admission'),
  aadhaar('aadhaar');

  const IdentifierType(this.code);

  /// Stored in the database; never change these strings.
  final String code;

  static IdentifierType? fromCode(String code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

enum StudentStatus { active, left, alumni, archived }

enum EnrollmentStatus { active, left, promoted, detained, graduated, transferred }

/// Fixed choice lists. Categories are editable per institution (Settings).
abstract final class StudentChoices {
  static const genders = ['Male', 'Female', 'Other'];
  static const relations = ['Father', 'Mother', 'Guardian', 'Other'];
  static const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const defaultCategories = ['Open', 'SC', 'ST', 'OBC', 'VJ/NT', 'SBC', 'EWS', 'Other'];
}

/// One guardian as entered in the student form.
class GuardianDraft {
  GuardianDraft({
    this.id,
    this.name = '',
    this.relation = 'Father',
    this.mobile = '',
    this.altMobile = '',
    this.email = '',
    this.occupation = '',
    this.isPrimary = false,
  });

  /// Existing guardian's id when editing; null for a new guardian.
  String? id;
  String name;
  String relation;
  String mobile;
  String altMobile;
  String email;
  String occupation;
  bool isPrimary;

  bool get isEmpty => name.trim().isEmpty && mobile.trim().isEmpty;
}

/// Everything the add/edit form collects.
class StudentDraft {
  StudentDraft({
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.altName = '',
    this.gender,
    this.dateOfBirth,
    this.placeOfBirth = '',
    this.nationality = 'Indian',
    this.motherTongue = '',
    this.category,
    this.caste = '',
    this.subCaste = '',
    this.bloodGroup,
    this.heightCm,
    this.weightKg,
    this.measuredOn,
    this.address = '',
    this.photoFileName,
    this.admissionDate,
    this.previousSchool = '',
    this.notes = '',
    List<GuardianDraft>? guardians,
    Map<IdentifierType, String>? identifiers,
    this.divisionId,
    this.rollNumber,
    Map<String, String>? extra,
  })  : guardians = guardians ?? [],
        identifiers = identifiers ?? {},
        extra = extra ?? {};

  String firstName;
  String middleName;
  String lastName;
  String altName;
  String? gender;
  DateTime? dateOfBirth;
  String placeOfBirth;
  String nationality;
  String motherTongue;
  String? category;
  String caste;
  String subCaste;
  String? bloodGroup;
  double? heightCm;
  double? weightKg;
  DateTime? measuredOn;
  String address;
  String? photoFileName;
  DateTime? admissionDate;
  String previousSchool;
  String notes;
  List<GuardianDraft> guardians;

  /// For Aadhaar: the full number when entered or changed; leave out to keep the stored one.
  Map<IdentifierType, String> identifiers;

  /// Division in the active academic year; null means not placed yet.
  String? divisionId;
  int? rollNumber;
  Map<String, String> extra;

  String get fullName => [firstName, middleName, lastName].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' ');
}

/// A row in the students list.
@immutable
class StudentListItem {
  const StudentListItem({
    required this.id,
    required this.displayCode,
    required this.fullName,
    required this.status,
    this.gender,
    this.photoFileName,
    this.divisionId,
    this.rollNumber,
    this.primaryMobile,
    this.grNumber,
    this.dateOfBirth,
  });

  final String id;
  final String displayCode;

  /// For age order in lists and reports.
  final DateTime? dateOfBirth;

  /// General Register number, when entered.
  final String? grNumber;
  final String fullName;
  final StudentStatus status;
  final String? gender;
  final String? photoFileName;
  final String? divisionId;
  final int? rollNumber;
  final String? primaryMobile;
}

@immutable
class GuardianInfo {
  const GuardianInfo({
    required this.id,
    required this.name,
    required this.relation,
    required this.isPrimary,
    this.mobile,
    this.altMobile,
    this.email,
    this.occupation,
  });

  final String id;
  final String name;
  final String relation;
  final bool isPrimary;
  final String? mobile;
  final String? altMobile;
  final String? email;
  final String? occupation;
}

@immutable
class IdentifierInfo {
  const IdentifierInfo({required this.type, required this.display});

  final IdentifierType type;

  /// The value, or for Aadhaar the masked form.
  final String display;
}

@immutable
class EnrollmentInfo {
  const EnrollmentInfo({
    required this.id,
    required this.academicYearId,
    required this.divisionId,
    required this.startDate,
    required this.status,
    this.rollNumber,
    this.endDate,
  });

  final String id;
  final String academicYearId;
  final String divisionId;
  final int? rollNumber;
  final DateTime startDate;
  final DateTime? endDate;
  final EnrollmentStatus status;
}

/// Everything shown on the student profile.
@immutable
class StudentDetail {
  const StudentDetail({
    required this.id,
    required this.displayCode,
    required this.status,
    required this.draft,
    required this.guardians,
    required this.identifiers,
    required this.enrollments,
    this.leavingDate,
    this.leavingReason,
    this.deletedAt,
  });

  final String id;
  final String displayCode;
  final StudentStatus status;

  /// The student's fields in editable form (Aadhaar left out).
  final StudentDraft draft;
  final List<GuardianInfo> guardians;
  final List<IdentifierInfo> identifiers;

  /// Newest first.
  final List<EnrollmentInfo> enrollments;
  final DateTime? leavingDate;
  final String? leavingReason;
  final DateTime? deletedAt;

  EnrollmentInfo? get activeEnrollment {
    for (final e in enrollments) {
      if (e.status == EnrollmentStatus.active) return e;
    }
    return null;
  }

  String? identifier(IdentifierType type) {
    for (final i in identifiers) {
      if (i.type == type) return i.display;
    }
    return null;
  }
}

/// Why an existing student looks like the one being saved.
enum DuplicateReason { sameNameAndBirthDate, sameIdentifier, sameMobileSimilarName }

@immutable
class DuplicateMatch {
  const DuplicateMatch({required this.studentId, required this.displayCode, required this.fullName, required this.reason});

  final String studentId;
  final String displayCode;
  final String fullName;
  final DuplicateReason reason;
}

enum StudentIssue {
  nameRequired,
  invalidAadhaar,
  invalidMobile,
  duplicateIdentifier,
  duplicateRoll,
  divisionNotInActiveYear,
  requiredFieldMissing,
  notFound,
}

class StudentValidationException implements Exception {
  const StudentValidationException(this.issue, [this.detail]);

  final StudentIssue issue;

  /// e.g. which identifier or field.
  final String? detail;

  @override
  String toString() => 'StudentValidationException(${issue.name}${detail == null ? '' : ': $detail'})';
}

/// An extra field defined by the institution.
@immutable
class ExtraFieldDefinition {
  const ExtraFieldDefinition({
    required this.id,
    required this.key,
    required this.label,
    required this.type,
    required this.options,
    required this.isRequired,
  });

  final String id;
  final String key;
  final String label;

  /// text, number, date, choice, yesNo
  final String type;
  final List<String> options;
  final bool isRequired;
}

/// The keys a photo file name can be matched against.
@immutable
class StudentKeys {
  const StudentKeys({
    required this.id,
    required this.fullName,
    required this.displayCode,
    required this.identifiers,
    required this.hasPhoto,
    this.divisionId,
    this.rollNumber,
  });

  final String id;
  final String fullName;
  final String displayCode;

  /// type code -> value (Aadhaar never included).
  final Map<String, String> identifiers;
  final bool hasPhoto;
  final String? divisionId;
  final int? rollNumber;
}

/// Extra facts a student list report may show, beyond the list item.
/// Aadhaar is only the masked form (last four digits); the full number
/// needs [StudentRepository.revealAadhaarFor].
@immutable
class StudentReportFacts {
  const StudentReportFacts({this.motherName, this.fatherName, this.aadhaarMasked, this.photoFileName});

  final String? motherName;
  final String? fatherName;

  /// "XXXX XXXX 7881", or null when no Aadhaar is recorded.
  final String? aadhaarMasked;
  final String? photoFileName;
}
