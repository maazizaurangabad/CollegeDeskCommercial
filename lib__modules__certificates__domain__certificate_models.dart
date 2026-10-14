import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The certificates the office issues. The code is stored; never rename.
enum CertificateKind {
  bonafide('BON'),
  leaving('LC'),
  noDues('ND'),
  noc('NOC'),
  character('CHR');

  const CertificateKind(this.prefix);

  /// Used in serial numbers, e.g. BON/2026-27/0001.
  final String prefix;

  static CertificateKind? byName(String name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

enum CertificateStatus { issued, cancelled }

/// Field keys shared by all certificates. Values are what gets printed.
abstract final class CertField {
  static const name = 'name';
  static const fatherName = 'father_name';
  static const motherName = 'mother_name';
  static const surname = 'surname';
  static const gender = 'gender';
  static const grNumber = 'gr_number';
  static const studentCode = 'student_code';
  static const pen = 'pen';
  static const apaar = 'apaar';
  static const saralId = 'saral_id';
  static const className = 'class_name';
  static const rollNumber = 'roll_number';
  static const academicYear = 'academic_year';
  static const dateOfBirth = 'date_of_birth';
  static const dateOfBirthWords = 'date_of_birth_words';
  static const placeOfBirth = 'place_of_birth';
  static const nationality = 'nationality';
  static const motherTongue = 'mother_tongue';
  static const religion = 'religion';
  static const casteSubcaste = 'caste_subcaste';
  static const category = 'category';
  static const previousSchool = 'previous_school';
  static const admissionDateClass = 'admission_date_class';
  static const progress = 'progress';
  static const conduct = 'conduct';
  static const leavingDate = 'leaving_date';
  static const studyingSince = 'studying_since';
  static const leavingReason = 'leaving_reason';
  static const remarks = 'remarks';
  static const purpose = 'purpose';
}

@immutable
class CertificateRecord {
  const CertificateRecord({
    required this.id,
    required this.kind,
    required this.serialLabel,
    required this.studentId,
    required this.issuedOn,
    required this.fields,
    required this.status,
    required this.isDuplicate,
    required this.printCount,
    this.cancelReason,
    this.lastPrintedAt,
  });

  final String id;
  final CertificateKind kind;
  final String serialLabel;
  final String studentId;
  final DateTime issuedOn;
  final Map<String, String> fields;
  final CertificateStatus status;
  final bool isDuplicate;
  final int printCount;
  final String? cancelReason;
  final DateTime? lastPrintedAt;

  String get studentName => fields[CertField.name] ?? '';

  static Map<String, String> decode(String json) =>
      (jsonDecode(json) as Map<String, dynamic>).map((k, v) => MapEntry(k, '${v ?? ''}'));
}

enum CertificateIssue { notFound, alreadyCancelled, noActiveYear }

class CertificateException implements Exception {
  const CertificateException(this.issue);

  final CertificateIssue issue;

  @override
  String toString() => 'CertificateException(${issue.name})';
}
