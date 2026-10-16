import 'dart:convert';

import 'package:flutter/foundation.dart';

enum DocumentStatus { received, pending, notNeeded }

/// A kind of paper students submit, as the institution sets it up.
@immutable
class DocumentType {
  const DocumentType({
    required this.key,
    required this.label,
    this.isRequired = false,
    this.onlyReserved = false,
    this.programIds = const [],
    this.sensitive = false,
  });

  final String key;
  final String label;

  /// Every student (of [programIds], if any) must submit it.
  final bool isRequired;

  /// Required only for students of a reserved category (not Open).
  final bool onlyReserved;

  /// Classes it is required for; empty means all classes.
  final List<String> programIds;

  /// Holds Aadhaar or similar: scans open only for users allowed to see Aadhaar.
  final bool sensitive;

  /// Whether this student must submit it.
  bool requiredFor({String? programId, String? category}) {
    if (!isRequired) return false;
    if (programIds.isNotEmpty && (programId == null || !programIds.contains(programId))) return false;
    if (onlyReserved && !isReservedCategory(category)) return false;
    return true;
  }

  DocumentType copyWith({String? label, bool? isRequired, bool? onlyReserved, List<String>? programIds, bool? sensitive}) =>
      DocumentType(
        key: key,
        label: label ?? this.label,
        isRequired: isRequired ?? this.isRequired,
        onlyReserved: onlyReserved ?? this.onlyReserved,
        programIds: programIds ?? this.programIds,
        sensitive: sensitive ?? this.sensitive,
      );

  Map<String, Object?> toJson() => {
        'key': key,
        'label': label,
        'required': isRequired,
        'onlyReserved': onlyReserved,
        'programIds': programIds,
        'sensitive': sensitive,
      };

  static DocumentType fromJson(Map<String, dynamic> j) => DocumentType(
        key: '${j['key']}',
        label: '${j['label']}',
        isRequired: j['required'] == true,
        onlyReserved: j['onlyReserved'] == true,
        programIds: [for (final p in (j['programIds'] as List<dynamic>? ?? const [])) '$p'],
        sensitive: j['sensitive'] == true,
      );
}

/// Open / General are not reserved; anything else recorded is.
bool isReservedCategory(String? category) {
  final c = (category ?? '').trim().toLowerCase();
  return c.isNotEmpty && c != 'open' && c != 'general';
}

abstract final class DocumentTypes {
  static const settingKey = 'students.document_types';

  static const defaults = [
    DocumentType(key: 'ssc_marksheet', label: '10th (SSC) Marksheet', isRequired: true),
    DocumentType(key: 'leaving_certificate', label: 'School Leaving Certificate / TC', isRequired: true),
    DocumentType(key: 'birth_certificate', label: 'Birth Certificate'),
    DocumentType(key: 'aadhaar_card', label: 'Aadhaar Card copy', isRequired: true, sensitive: true),
    DocumentType(key: 'caste_certificate', label: 'Caste Certificate', isRequired: true, onlyReserved: true),
    DocumentType(key: 'non_creamy_layer', label: 'Non-Creamy Layer Certificate'),
    DocumentType(key: 'income_certificate', label: 'Income Certificate'),
    DocumentType(key: 'domicile_certificate', label: 'Domicile Certificate'),
    DocumentType(key: 'photos', label: 'Passport-size photos', isRequired: true),
    DocumentType(key: 'migration_certificate', label: 'Migration Certificate (other boards)'),
  ];

  /// Saved list, or the defaults when nothing is saved yet.
  static List<DocumentType> decode(String? raw) {
    if (raw == null) return defaults;
    try {
      return [for (final j in jsonDecode(raw) as List<dynamic>) DocumentType.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return defaults;
    }
  }

  static String encode(List<DocumentType> types) => jsonEncode([for (final t in types) t.toJson()]);

  /// A key for a new type from its name ("Bonafide copy" -> bonafide_copy).
  static String keyFor(String label, Iterable<String> taken) {
    var base = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    if (base.isEmpty) base = 'document';
    var key = base, n = 2;
    while (taken.contains(key)) {
      key = '${base}_${n++}';
    }
    return key;
  }
}

/// One document record of a student.
@immutable
class StudentDocument {
  const StudentDocument({
    this.id,
    required this.studentId,
    required this.typeKey,
    this.status = DocumentStatus.received,
    this.number,
    this.issuedOn,
    this.isOriginal = false,
    this.returnedOn,
    this.verified = false,
    this.note,
    this.files = const [],
    this.updatedAt,
  });

  /// Null until saved.
  final String? id;
  final String studentId;
  final String typeKey;
  final DocumentStatus status;
  final String? number;
  final DateTime? issuedOn;

  /// The original is with the office (not just a copy).
  final bool isOriginal;

  /// When the original was given back to the student.
  final DateTime? returnedOn;
  final bool verified;
  final String? note;

  /// Scanned pages / files, inside the media folder, in order.
  final List<String> files;
  final DateTime? updatedAt;

  bool get hasFiles => files.isNotEmpty;

  StudentDocument copyWith({
    String? id,
    DocumentStatus? status,
    String? number,
    DateTime? issuedOn,
    bool clearIssuedOn = false,
    bool? isOriginal,
    DateTime? returnedOn,
    bool clearReturnedOn = false,
    bool? verified,
    String? note,
    List<String>? files,
  }) =>
      StudentDocument(
        id: id ?? this.id,
        studentId: studentId,
        typeKey: typeKey,
        status: status ?? this.status,
        number: number ?? this.number,
        issuedOn: clearIssuedOn ? null : (issuedOn ?? this.issuedOn),
        isOriginal: isOriginal ?? this.isOriginal,
        returnedOn: clearReturnedOn ? null : (returnedOn ?? this.returnedOn),
        verified: verified ?? this.verified,
        note: note ?? this.note,
        files: files ?? this.files,
        updatedAt: updatedAt,
      );
}

/// One line of a student's checklist: the type, its record (if any) and
/// whether it is required for this student.
typedef DocumentLine = ({DocumentType type, StudentDocument? document, bool isRequired});

/// Every type, in the institution's order, plus records of types removed
/// later (kept so nothing disappears).
List<DocumentLine> documentChecklist(
  List<DocumentType> types,
  List<StudentDocument> documents, {
  String? programId,
  String? category,
}) {
  final byType = {for (final d in documents) d.typeKey: d};
  final known = types.map((t) => t.key).toSet();
  return [
    for (final t in types)
      (type: t, document: byType[t.key], isRequired: t.requiredFor(programId: programId, category: category)),
    for (final d in documents)
      if (!known.contains(d.typeKey))
        (type: DocumentType(key: d.typeKey, label: d.typeKey.replaceAll('_', ' ')), document: d, isRequired: false),
  ];
}

/// A required document not yet received (and not marked "not needed").
bool isMissing(DocumentLine line) =>
    line.isRequired && (line.document == null || line.document!.status == DocumentStatus.pending);
