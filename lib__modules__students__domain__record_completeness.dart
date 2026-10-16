import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'student_models.dart';

/// Things the profile can check are filled in. Each institution chooses
/// which ones count (Settings > Student fields); own fields marked
/// "required" always count. This is a checklist of what is recorded, not an
/// official verification of the values.
enum CompletenessCheck {
  fullName,
  dateOfBirth,
  gender,
  guardianMobile,
  classThisYear,
  grNumber,
  motherName,
  fatherName,
  address,
  category,
  admissionDate,
  aadhaar,
  pen,
  apaar,
  photo,

  /// Every required document received (or marked "not needed").
  requiredDocuments,
}

/// The important items that count when the institution has not chosen.
const defaultCompletenessChecks = <CompletenessCheck>{
  CompletenessCheck.fullName,
  CompletenessCheck.dateOfBirth,
  CompletenessCheck.gender,
  CompletenessCheck.guardianMobile,
  CompletenessCheck.classThisYear,
  CompletenessCheck.grNumber,
  // Needed for HSC / SSC board forms.
  CompletenessCheck.motherName,
};

/// One line of the checklist: a standard check or a required own field.
@immutable
class CompletenessItem {
  const CompletenessItem.check(CompletenessCheck this.check, {required this.done}) : extraField = null;
  const CompletenessItem.extra(ExtraFieldDefinition this.extraField, {required this.done}) : check = null;

  final CompletenessCheck? check;
  final ExtraFieldDefinition? extraField;
  final bool done;
}

@immutable
class RecordCompleteness {
  const RecordCompleteness(this.items);

  final List<CompletenessItem> items;

  int get done => items.where((i) => i.done).length;
  int get total => items.length;

  /// Whole percent; 100 when nothing is checked.
  int get percent => total == 0 ? 100 : (done * 100 / total).round();
  List<CompletenessItem> get missing => items.where((i) => !i.done).toList();

  /// Works out the checklist. [academicYearId] is the year the profile
  /// shows (for "class this year"). Nothing here reveals a value: Aadhaar
  /// is only checked for being recorded. [documentsMissing] is how many
  /// required documents are still pending (null while not known).
  static RecordCompleteness evaluate(
    StudentDetail detail, {
    required Set<CompletenessCheck> checks,
    required List<ExtraFieldDefinition> extraFields,
    String? academicYearId,
    int? documentsMissing,
  }) {
    final d = detail.draft;
    bool filled(String? v) => v != null && v.trim().isNotEmpty;
    bool guardianNamed(String relation) =>
        detail.guardians.any((g) => g.relation.toLowerCase() == relation.toLowerCase() && filled(g.name));

    bool isDone(CompletenessCheck c) => switch (c) {
          CompletenessCheck.fullName => filled(d.fullName),
          CompletenessCheck.dateOfBirth => d.dateOfBirth != null,
          CompletenessCheck.gender => filled(d.gender),
          CompletenessCheck.guardianMobile => detail.guardians.any((g) => filled(g.mobile)),
          CompletenessCheck.classThisYear =>
            academicYearId != null && detail.enrollments.any((e) => e.academicYearId == academicYearId),
          CompletenessCheck.grNumber => filled(detail.identifier(IdentifierType.grNumber)),
          CompletenessCheck.motherName => guardianNamed('Mother'),
          CompletenessCheck.fatherName => guardianNamed('Father'),
          CompletenessCheck.address => filled(d.address),
          CompletenessCheck.category => filled(d.category),
          CompletenessCheck.admissionDate => d.admissionDate != null,
          CompletenessCheck.aadhaar => filled(detail.identifier(IdentifierType.aadhaar)),
          CompletenessCheck.pen => filled(detail.identifier(IdentifierType.pen)),
          CompletenessCheck.apaar => filled(detail.identifier(IdentifierType.apaar)),
          CompletenessCheck.photo => filled(d.photoFileName),
          CompletenessCheck.requiredDocuments => documentsMissing == 0,
        };

    return RecordCompleteness([
      for (final c in CompletenessCheck.values)
        if (checks.contains(c)) CompletenessItem.check(c, done: isDone(c)),
      for (final f in extraFields)
        if (f.isRequired) CompletenessItem.extra(f, done: filled(d.extra[f.key])),
    ]);
  }

  /// Saved as a JSON list of names; unknown names are ignored.
  /// Nothing saved yet means the defaults.
  static Set<CompletenessCheck> decodeChecks(String? raw) {
    if (raw == null) return defaultCompletenessChecks;
    try {
      final names = (jsonDecode(raw) as List<dynamic>).map((e) => '$e').toSet();
      return {
        for (final c in CompletenessCheck.values)
          if (names.contains(c.name)) c,
      };
    } catch (_) {
      return defaultCompletenessChecks;
    }
  }

  static String encodeChecks(Set<CompletenessCheck> checks) =>
      jsonEncode([for (final c in CompletenessCheck.values) if (checks.contains(c)) c.name]);
}
